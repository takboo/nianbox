// Guest-only conflict fixture, never a host global key registration.
import AppKit
import Carbon.HIToolbox
import Foundation

@main struct ShortcutHolder {
    static func main() throws {
        let identity = Process(); let pipe = Pipe()
        identity.executableURL = URL(fileURLWithPath: "/usr/sbin/sysctl")
        identity.arguments = ["-n", "hw.model"]; identity.standardOutput = pipe
        try identity.run(); identity.waitUntilExit()
        let model = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard model.hasPrefix("VirtualMac") else { fatalError("Refusing hotkey registration on a physical Mac") }
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        var reference: EventHotKeyRef?
        let result = RegisterEventHotKey(37, UInt32(controlKey | optionKey),
            EventHotKeyID(signature: 0x4E425453, id: 1), GetApplicationEventTarget(), 0, &reference)
        guard result == noErr else { fatalError("Cannot reserve conflict fixture: \(result)") }
        print("READY"); fflush(stdout)
        app.run()
    }
}
