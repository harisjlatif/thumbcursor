// Minimal test runner for Engine (no XCTest needed). Run with `make test`.

var failures = 0

func check(_ name: String, _ events: [KeyEvent], _ expected: [Output], line: Int = #line) {
    let engine = Engine()
    let actual = events.flatMap { engine.handle($0) }
    if actual == expected {
        print("ok   \(name)")
    } else {
        failures += 1
        print("FAIL \(name) (line \(line))\n  expected: \(expected)\n  actual:   \(actual)")
    }
}

func down(_ k: UInt16, _ flags: UInt64 = 0, repeat r: Bool = false) -> KeyEvent {
    KeyEvent(keyCode: k, isDown: true, isRepeat: r, flags: flags)
}
func up(_ k: UInt16, _ flags: UInt64 = 0) -> KeyEvent {
    KeyEvent(keyCode: k, isDown: false, flags: flags)
}
func key(_ k: UInt16, _ d: Bool, _ flags: UInt64 = 0) -> Output { .key(code: k, down: d, flags: flags) }

let sp = KeyCode.space
let a: UInt16 = 0
let arrow = Flag.function | Flag.numericPad
let spaceTap = [key(sp, true), key(sp, false)]

check("tap space types a space", [down(sp), up(sp)], spaceTap)

check("space auto-repeat is swallowed", [down(sp), down(sp, repeat: true), up(sp)], spaceTap)

check("ordinary keys pass through", [down(a), up(a)], [.original, .original])

check("space+j gives left arrow",
      [down(sp), down(KeyCode.j), up(KeyCode.j), up(sp)],
      [key(KeyCode.left, true, arrow), key(KeyCode.left, false, arrow)])

check("holding space+j repeats left arrow",
      [down(sp), down(KeyCode.j), down(KeyCode.j, repeat: true), down(KeyCode.j, repeat: true), up(KeyCode.j), up(sp)],
      [key(KeyCode.left, true, arrow), key(KeyCode.left, true, arrow), key(KeyCode.left, false, arrow)])

check("rollover: space released before l types ' l'",
      [down(sp), down(KeyCode.l), up(sp), up(KeyCode.l)],
      spaceTap + [key(KeyCode.l, true), .original])

check("unmapped key while space held types ' a'",
      [down(sp), down(a), up(a), up(sp)],
      spaceTap + [.original, .original])

check("multiple layer keys in one hold",
      [down(sp), down(KeyCode.i), up(KeyCode.i), down(KeyCode.k), up(KeyCode.k), up(sp)],
      [key(KeyCode.up, true, arrow), key(KeyCode.up, false, arrow),
       key(KeyCode.down, true, arrow), key(KeyCode.down, false, arrow)])

check("second key commits deferred key (j then l rolled)",
      [down(sp), down(KeyCode.j), down(KeyCode.l), up(KeyCode.j), up(KeyCode.l), up(sp)],
      [key(KeyCode.left, true, arrow), key(KeyCode.right, true, arrow),
       key(KeyCode.left, false, arrow), key(KeyCode.right, false, arrow)])

let sh = Flag.shift
check("shift passes through: space+shift+j selects left",
      [down(sp), down(KeyCode.j, sh), up(KeyCode.j, sh), up(sp)],
      [key(KeyCode.left, true, arrow | sh), key(KeyCode.left, false, arrow | sh)])

check("space+u is cmd+left (line start)",
      [down(sp), down(KeyCode.u), up(KeyCode.u), up(sp)],
      [key(KeyCode.left, true, arrow | Flag.command), key(KeyCode.left, false, arrow | Flag.command)])

check("space+m is forward delete",
      [down(sp), down(KeyCode.m), up(KeyCode.m), up(sp)],
      [key(KeyCode.forwardDelete, true, Flag.function), key(KeyCode.forwardDelete, false, Flag.function)])

check("cmd+space passes through untouched",
      [down(sp, Flag.command), up(sp, Flag.command)],
      [.original, .original])

check("space released while mapped key held: key-up still mapped",
      [down(sp), down(KeyCode.j), down(KeyCode.j, repeat: true), up(sp), down(KeyCode.j, repeat: true), up(KeyCode.j)],
      [key(KeyCode.left, true, arrow), key(KeyCode.left, true, arrow), key(KeyCode.left, false, arrow)])

check("shift+space types shift+space",
      [down(sp, sh), up(sp, sh)],
      [key(sp, true, sh), key(sp, false, sh)])

check("normal typing after layer use",
      [down(sp), down(KeyCode.j), up(KeyCode.j), up(sp), down(KeyCode.j), up(KeyCode.j)],
      [key(KeyCode.left, true, arrow), key(KeyCode.left, false, arrow), .original, .original])

if failures > 0 {
    print("\n\(failures) test(s) failed")
    exit(1)
}
print("\nall tests passed")

import Foundation
