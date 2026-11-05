// TouchCursor for macOS: connects the Engine state machine to a CGEventTap.

import ApplicationServices
import Foundation

/// Marks events we synthesize so our own tap ignores them.
let marker: Int64 = 0x5443_5552  // "TCUR"

let engine = Engine()
let source = CGEventSource(stateID: .privateState)
var tap: CFMachPort?

func log(_ message: String) {
    FileHandle.standardError.write("\(Date()) \(message)\n".data(using: .utf8)!)
}

func callback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        log("event tap disabled (\(type.rawValue)), re-enabling")
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    guard type == .keyDown || type == .keyUp,
          event.getIntegerValueField(.eventSourceUserData) != marker
    else { return Unmanaged.passUnretained(event) }

    let outputs = engine.handle(KeyEvent(
        keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
        isDown: type == .keyDown,
        isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
        flags: event.flags.rawValue))

    if outputs == [.original] { return Unmanaged.passUnretained(event) }

    for output in outputs {
        switch output {
        case .original:
            guard let copy = event.copy() else { continue }
            copy.setIntegerValueField(.eventSourceUserData, value: marker)
            copy.tapPostEvent(proxy)
        case let .key(code, down, flags):
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            e.flags = CGEventFlags(rawValue: flags)
            e.setIntegerValueField(.eventSourceUserData, value: marker)
            e.tapPostEvent(proxy)
        }
    }
    return nil
}

func installTap() -> Bool {
    let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
    guard let port = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(mask),
        callback: callback,
        userInfo: nil)
    else { return false }

    tap = port
    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: port, enable: true)
    log("TouchCursor running")
    return true
}

// Ask for Accessibility permission (shows the system prompt once), then wait for it.
let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
if !AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) {
    log("waiting for Accessibility permission (System Settings > Privacy & Security > Accessibility)")
}

Timer.scheduledTimer(withTimeInterval: 0, repeats: false) { _ in
    func attempt() {
        if AXIsProcessTrusted() && installTap() { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: attempt)
    }
    attempt()
}

CFRunLoopRun()
