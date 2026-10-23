import Carbon.HIToolbox

@MainActor
final class GlobalHotKey {
    private static let signature: OSType = 0x4E424F58 // "NBOX"
    private var shortcut: QuickCaptureShortcut?
    private var identifier: UInt32 = 0
    private let action: @MainActor () -> Void
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?

    init(action: @escaping @MainActor () -> Void) { self.action = action }

    func replace(with candidate: QuickCaptureShortcut?) throws {
        guard let candidate else { unregister(); return }
        guard candidate.isValid else { throw ShortcutError.invalid }
        if shortcut == candidate, hotKeyReference != nil { return }
        if eventHandlerReference == nil { try installHandler() }
        let nextID = identifier &+ 1
        var nextReference: EventHotKeyRef?
        let status = RegisterEventHotKey(candidate.keyCode, candidate.modifiers,
            EventHotKeyID(signature: Self.signature, id: nextID), GetApplicationEventTarget(), 0, &nextReference)
        guard status == noErr else { throw ShortcutError.registration(status) }
        if let hotKeyReference { UnregisterEventHotKey(hotKeyReference) }
        hotKeyReference = nextReference
        shortcut = candidate
        identifier = nextID
    }

    private func installHandler() throws {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return noErr }

                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard status == noErr, identifier.signature == GlobalHotKey.signature else {
                    return noErr
                }

                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
                guard identifier.id == hotKey.identifier else { return noErr }
                Task { @MainActor in hotKey.action() }
                return noErr
            },
            1,
            &eventType,
            context,
            &eventHandlerReference
        )
        guard installStatus == noErr else { throw ShortcutError.registration(installStatus) }
    }

    func unregister() {
        if let hotKeyReference { UnregisterEventHotKey(hotKeyReference) }
        if let eventHandlerReference { RemoveEventHandler(eventHandlerReference) }
        hotKeyReference = nil
        eventHandlerReference = nil
        shortcut = nil
    }
}
