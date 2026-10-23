// Native acceptance helper for an isolated macOS VM. Refuses physical Macs.
import AppKit
import ApplicationServices
import Foundation

struct ProbeFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@main
struct VMUIProbe {
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }
    static func string(_ element: AXUIElement, _ name: String) -> String? { attribute(element, name) as? String }
    static func rect(_ element: AXUIElement) -> CGRect {
        var point = CGPoint.zero
        var size = CGSize.zero
        if let value = attribute(element, "AXPosition"), CFGetTypeID(value) == AXValueGetTypeID() {
            AXValueGetValue(value as! AXValue, .cgPoint, &point)
        }
        if let value = attribute(element, "AXSize"), CFGetTypeID(value) == AXValueGetTypeID() {
            AXValueGetValue(value as! AXValue, .cgSize, &size)
        }
        return CGRect(origin: point, size: size)
    }
    static func walk(_ root: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 18 else { return [] }
        let children = attribute(root, "AXChildren") as? [AXUIElement] ?? []
        return [root] + children.flatMap { walk($0, depth: depth + 1) }
    }
    static func find(_ root: AXUIElement, _ selector: String) throws -> AXUIElement {
        let parts = selector.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw ProbeFailure(message: "Use id=... or text=...") }
        guard let element = walk(root).first(where: { element in
            if parts[0] == "id" { return string(element, "AXIdentifier") == parts[1] }
            if parts[0] == "subrole" { return string(element, "AXSubrole") == parts[1] }
            return ["AXTitle", "AXValue", "AXDescription"].contains { string(element, $0) == parts[1] }
        }) else { throw ProbeFailure(message: "Element not found: \(selector)") }
        return element
    }
    static func settle(_ seconds: TimeInterval = 0.3) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
    static func mouse(_ type: CGEventType, _ point: CGPoint, clicks: Int64 = 1) {
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!
        event.flags = []
        event.setIntegerValueField(.mouseEventClickState, value: clicks)
        event.post(tap: .cghidEventTap)
    }
    static func click(_ point: CGPoint, twice: Bool = false) {
        mouse(.mouseMoved, point); settle(0.1)
        mouse(.leftMouseDown, point); settle(0.08)
        mouse(.leftMouseUp, point)
        if twice { settle(0.08); mouse(.leftMouseDown, point, clicks: 2); mouse(.leftMouseUp, point, clicks: 2) }
        settle()
    }
    static func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
            event.flags = down ? flags : []
            event.post(tap: .cghidEventTap)
            settle(0.05)
        }
        settle()
    }
    static func output(_ value: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    }
    static func main() {
        do { try run() }
        catch {
            fputs("VM UI probe: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    static func run() throws {
        let identity = Process()
        let pipe = Pipe()
        identity.executableURL = URL(fileURLWithPath: "/usr/sbin/sysctl")
        identity.arguments = ["-n", "hw.model"]
        identity.standardOutput = pipe
        try identity.run(); identity.waitUntilExit()
        let model = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard model.hasPrefix("VirtualMac") else { throw ProbeFailure(message: "Refusing desktop input on a physical Mac") }
        guard AXIsProcessTrusted() else { throw ProbeFailure(message: "Guest Accessibility authorization is required") }
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count >= 2, let pid = pid_t(args[1]),
              let app = NSRunningApplication(processIdentifier: pid), app.bundleIdentifier == "org.nianbox.NianBox" else {
            throw ProbeFailure(message: "Usage: probe <dump|click|double|type|key|drag|move> <NianBox-pid> [arguments]")
        }
        let root = AXUIElementCreateApplication(pid)
        if args[0] == "windows" {
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            let own = windows.filter { ($0[kCGWindowOwnerPID as String] as? Int) == Int(pid) }
            try output(["windows": own])
            return
        }
        if args[0] == "dump" {
            let nodes: [[String: Any]] = walk(root).filter { rect($0).width > 0 && rect($0).height > 0 }.map { element in
                let bounds = rect(element)
                var node: [String: Any] = ["role": string(element, "AXRole") ?? "", "x": bounds.minX,
                    "y": bounds.minY, "width": bounds.width, "height": bounds.height]
                for field in ["AXIdentifier", "AXTitle", "AXDescription", "AXValue", "AXSubrole"] {
                    if field == "AXValue", string(element, "AXSubrole") == "AXSecureTextField" { continue }
                    if let value = string(element, field), !value.isEmpty { node[field] = value }
                }
                if let url = attribute(element, "AXURL") as? URL { node["AXURL"] = url.absoluteString }
                return node
            }
            try output(["guestModel": model.trimmingCharacters(in: .whitespacesAndNewlines), "pid": pid, "nodes": nodes])
            return
        }
        if !["key", "move"].contains(args[0]) { app.activate(options: []); settle(0.15) }
        switch args[0] {
        case "press":
            let result = AXUIElementPerformAction(try find(root, args[2]), kAXPressAction as CFString)
            guard result == .success else { throw ProbeFailure(message: "AXPress failed: \(result.rawValue)") }
            settle()
        case "click", "double":
            let bounds = rect(try find(root, args[2]))
            click(CGPoint(x: bounds.midX, y: bounds.midY), twice: args[0] == "double")
        case "type":
            let text = Array(args[2].utf16)
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
            event.flags = []
            text.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength: text.count, unicodeString: $0.baseAddress) }
            event.post(tap: .cghidEventTap); settle(0.05)
            let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)!
            up.flags = []
            up.post(tap: .cghidEventTap); settle()
        case "key":
            switch args[2] {
            case "return": key(36)
            case "escape": key(53)
            case "selectAll": key(0, flags: .maskCommand)
            case "shortcut": key(49, flags: [.maskControl, .maskAlternate])
            case "captureK": key(40, flags: [.maskControl, .maskAlternate])
            case "captureL": key(37, flags: [.maskControl, .maskAlternate])
            case "delete": key(51)
            default: throw ProbeFailure(message: "Unknown key")
            }
        case "move":
            mouse(.mouseMoved, CGPoint(x: Double(args[2])!, y: Double(args[3])!)); settle(0.7)
        case "drag":
            let from = rect(try find(root, args[2]))
            let start = CGPoint(x: from.midX, y: from.midY)
            mouse(.mouseMoved, start); mouse(.leftMouseDown, start); settle(0.15)
            var position = CGPoint(x: start.x + 10, y: start.y + 3)
            mouse(.leftMouseDragged, position); settle(0.7)
            let destination = rect(try find(root, args[3]))
            let target = CGPoint(x: destination.midX, y: destination.midY)
            for step in 1...24 {
                let fraction = CGFloat(step) / 24
                position = CGPoint(x: start.x + (target.x - start.x) * fraction, y: start.y + (target.y - start.y) * fraction)
                mouse(.leftMouseDragged, position); settle(0.03)
            }
            settle(0.3)
            let latest = rect(try find(root, args[3]))
            position = CGPoint(x: latest.midX, y: latest.midY)
            mouse(.leftMouseDragged, position); settle(0.15); mouse(.leftMouseUp, position); settle(0.6)
        default: throw ProbeFailure(message: "Unknown command")
        }
        try output(["ok": true, "command": args[0]])
    }
}
