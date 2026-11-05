// Thumbcursor state machine.
//
// Pure logic with no CoreGraphics dependency so it can be unit tested.
// Behaviour follows the original Windows TouchCursor:
//
//   * Tapping space types a space.
//   * Holding space turns the right-hand letter keys into navigation keys.
//   * Rollover while typing is respected: if space is released *before* a
//     mapped key is released (e.g. typing " l" quickly), you get a space
//     followed by the letter, not an arrow.
//   * Pressing an unmapped key while space is held types the space and the key.

public struct KeyEvent: Equatable {
    public var keyCode: UInt16
    public var isDown: Bool
    public var isRepeat: Bool
    public var flags: UInt64

    public init(keyCode: UInt16, isDown: Bool, isRepeat: Bool = false, flags: UInt64 = 0) {
        self.keyCode = keyCode
        self.isDown = isDown
        self.isRepeat = isRepeat
        self.flags = flags
    }
}

public enum Output: Equatable {
    /// Let the original event through at this point in the sequence.
    case original
    /// Emit a synthesized key event.
    case key(code: UInt16, down: Bool, flags: UInt64)
}

/// CGEventFlags raw values.
public enum Flag {
    public static let capsLock: UInt64 = 0x0001_0000
    public static let shift: UInt64 = 0x0002_0000
    public static let control: UInt64 = 0x0004_0000
    public static let option: UInt64 = 0x0008_0000
    public static let command: UInt64 = 0x0010_0000
    public static let numericPad: UInt64 = 0x0020_0000
    public static let function: UInt64 = 0x0080_0000

    /// Modifier bits carried over from the physical keyboard into synthesized events.
    public static let userModifiers = capsLock | shift | control | option | command
}

/// macOS virtual key codes (ANSI positions).
public enum KeyCode {
    public static let space: UInt16 = 49
    public static let returnKey: UInt16 = 36
    public static let backspace: UInt16 = 51
    public static let escape: UInt16 = 53
    public static let forwardDelete: UInt16 = 117
    public static let left: UInt16 = 123
    public static let right: UInt16 = 124
    public static let down: UInt16 = 125
    public static let up: UInt16 = 126

    public static let q: UInt16 = 12
    public static let h: UInt16 = 4
    public static let o: UInt16 = 31
    public static let u: UInt16 = 32
    public static let i: UInt16 = 34
    public static let p: UInt16 = 35
    public static let l: UInt16 = 37
    public static let j: UInt16 = 38
    public static let k: UInt16 = 40
    public static let m: UInt16 = 46
}

public struct Mapping: Equatable {
    public var keyCode: UInt16
    /// Flags always added to the output (e.g. ⌘ for line start/end, fn for arrows).
    public var extraFlags: UInt64

    public init(_ keyCode: UInt16, _ extraFlags: UInt64 = 0) {
        self.keyCode = keyCode
        self.extraFlags = extraFlags
    }
}

private let arrowFlags = Flag.function | Flag.numericPad

/// Space + key → output. Edit this table to customise.
public let defaultMappings: [UInt16: Mapping] = [
    KeyCode.i: Mapping(KeyCode.up, arrowFlags),
    KeyCode.k: Mapping(KeyCode.down, arrowFlags),
    KeyCode.j: Mapping(KeyCode.left, arrowFlags),
    KeyCode.l: Mapping(KeyCode.right, arrowFlags),
    KeyCode.u: Mapping(KeyCode.left, arrowFlags | Flag.command),   // start of line
    KeyCode.o: Mapping(KeyCode.right, arrowFlags | Flag.command),  // end of line
    KeyCode.p: Mapping(KeyCode.backspace),
    KeyCode.m: Mapping(KeyCode.forwardDelete, Flag.function),
    KeyCode.h: Mapping(KeyCode.returnKey),
    KeyCode.q: Mapping(KeyCode.escape),
]

public final class Engine {
    enum State: Equatable {
        /// Space is not held.
        case idle
        /// Space is held and nothing else has been pressed yet.
        case spaceHeld
        /// Space is held and a mapped key went down; we wait to see which is released first.
        case deferred(key: UInt16, flags: UInt64)
        /// The navigation layer is active.
        case mapping
        /// An unmapped key was pressed while space was held, so the space was already typed.
        case spaceTyped
    }

    let mappings: [UInt16: Mapping]
    private(set) var state: State = .idle
    private var spaceFlags: UInt64 = 0
    /// Physical keys whose mapped key-down was emitted, so the matching key-up is mapped too.
    private var heldMapped: [UInt16: Mapping] = [:]

    public init(mappings: [UInt16: Mapping] = defaultMappings) {
        self.mappings = mappings
    }

    public func handle(_ e: KeyEvent) -> [Output] {
        e.keyCode == KeyCode.space ? handleSpace(e) : handleOther(e)
    }

    // MARK: - Space

    private func handleSpace(_ e: KeyEvent) -> [Output] {
        let flags = e.flags & Flag.userModifiers
        switch state {
        case .idle:
            // Leave ⌘-space / ⌃-space (Spotlight, input sources) alone.
            guard e.isDown, !e.isRepeat, flags & (Flag.command | Flag.control) == 0 else {
                return [.original]
            }
            state = .spaceHeld
            spaceFlags = flags
            return []

        case .spaceHeld:
            if e.isDown { return [] }
            state = .idle
            return typeSpace()

        case let .deferred(key, keyFlags):
            if e.isDown { return [] }
            // Space released before the mapped key: the user was typing.
            state = .idle
            return typeSpace() + [.key(code: key, down: true, flags: keyFlags)]

        case .mapping, .spaceTyped:
            if !e.isDown { state = .idle }
            return []
        }
    }

    private func typeSpace() -> [Output] {
        [.key(code: KeyCode.space, down: true, flags: spaceFlags),
         .key(code: KeyCode.space, down: false, flags: spaceFlags)]
    }

    // MARK: - Other keys

    private func handleOther(_ e: KeyEvent) -> [Output] {
        let flags = e.flags & Flag.userModifiers

        if !e.isDown {
            if let m = heldMapped.removeValue(forKey: e.keyCode) {
                return [mapped(m, down: false, flags: flags)]
            }
            if case let .deferred(key, keyFlags) = state, key == e.keyCode {
                // Mapped key released while space still held: commit to the layer.
                state = .mapping
                let m = mappings[key]!
                return [mapped(m, down: true, flags: keyFlags), mapped(m, down: false, flags: flags)]
            }
            return [.original]
        }

        // Auto-repeat of a key that is already mapped keeps repeating the mapped key,
        // even if space was released in the meantime.
        if let m = heldMapped[e.keyCode] {
            return [mapped(m, down: true, flags: flags)]
        }

        switch state {
        case .idle, .spaceTyped:
            return [.original]

        case .spaceHeld:
            if mappings[e.keyCode] != nil {
                state = .deferred(key: e.keyCode, flags: flags)
                return []
            }
            state = .spaceTyped
            return typeSpace() + [.original]

        case let .deferred(key, keyFlags):
            // Key held long enough to auto-repeat, or another key pressed: commit to the layer.
            state = .mapping
            let commit = emitMappedDown(key, flags: keyFlags)
            if key == e.keyCode { return commit }
            return commit + handleOther(e)

        case .mapping:
            if mappings[e.keyCode] != nil {
                return emitMappedDown(e.keyCode, flags: flags)
            }
            return [.original]
        }
    }

    private func emitMappedDown(_ key: UInt16, flags: UInt64) -> [Output] {
        let m = mappings[key]!
        heldMapped[key] = m
        return [mapped(m, down: true, flags: flags)]
    }

    private func mapped(_ m: Mapping, down: Bool, flags: UInt64) -> Output {
        .key(code: m.keyCode, down: down, flags: flags | m.extraFlags)
    }
}
