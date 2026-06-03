import Foundation
import Carbon

/// A selectable global hotkey combination.
struct HotKeyCombo: Identifiable, Equatable {
    let id: String
    let name: String
    let keyCode: UInt32
    let modifiers: UInt32

    static let all: [HotKeyCombo] = [
        .init(id: "optSpace",      name: "⌥ Space",   keyCode: 49, modifiers: UInt32(optionKey)),
        .init(id: "ctrlSpace",     name: "⌃ Space",   keyCode: 49, modifiers: UInt32(controlKey)),
        .init(id: "optShiftSpace", name: "⌥⇧ Space",  keyCode: 49, modifiers: UInt32(optionKey | shiftKey)),
        .init(id: "ctrlOptSpace",  name: "⌃⌥ Space",  keyCode: 49, modifiers: UInt32(controlKey | optionKey)),
        .init(id: "optR",          name: "⌥ R",       keyCode: 15, modifiers: UInt32(optionKey)),
        .init(id: "cmdShiftR",     name: "⌘⇧ R",      keyCode: 15, modifiers: UInt32(cmdKey | shiftKey)),
        .init(id: "ctrlOptR",      name: "⌃⌥ R",      keyCode: 15, modifiers: UInt32(controlKey | optionKey)),
        .init(id: "cmdShiftJ",     name: "⌘⇧ J",      keyCode: 38, modifiers: UInt32(cmdKey | shiftKey))
    ]

    static func byID(_ id: String) -> HotKeyCombo {
        all.first { $0.id == id } ?? all[0]
    }
}

/// Registers one or more global hotkeys via Carbon RegisterEventHotKey. Works
/// system-wide without Accessibility permission. A single installed event
/// handler dispatches to the right closure by hotkey id.
final class HotKeyManager {
    struct Binding {
        let id: UInt32
        let keyCode: UInt32
        let modifiers: UInt32
        let handler: () -> Void
    }

    private var refs: [EventHotKeyRef] = []
    private var handlers: [UInt32: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?

    init() {
        installHandler()
    }

    private func installHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handlers[hkID.id]?()
            return noErr
        }, 1, &eventType, selfPtr, &eventHandler)
    }

    /// Replaces all current hotkey registrations with the given bindings.
    func setBindings(_ bindings: [Binding]) {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        handlers.removeAll()

        for b in bindings {
            handlers[b.id] = b.handler
            let hotKeyID = EventHotKeyID(signature: OSType(0x52575254 /* 'RWRT' */), id: b.id)
            var ref: EventHotKeyRef?
            RegisterEventHotKey(b.keyCode, b.modifiers, hotKeyID,
                                GetApplicationEventTarget(), 0, &ref)
            if let ref { refs.append(ref) }
        }
    }

    deinit {
        for ref in refs { UnregisterEventHotKey(ref) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
