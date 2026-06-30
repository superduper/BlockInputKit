import AppKit
import XCTest
@testable import BlockInputKit

func mouseDownEvent(windowNumber: Int) throws -> NSEvent {
    try mouseEvent(type: .leftMouseDown, windowNumber: windowNumber)
}

func mouseDownEvent(
    location: NSPoint,
    windowNumber: Int,
    modifierFlags: NSEvent.ModifierFlags = [],
    clickCount: Int = 1
) throws -> NSEvent {
    try mouseEvent(
        type: .leftMouseDown,
        location: location,
        windowNumber: windowNumber,
        modifierFlags: modifierFlags,
        clickCount: clickCount
    )
}

func mouseDraggedEvent(location: NSPoint, windowNumber: Int) throws -> NSEvent {
    try mouseEvent(type: .leftMouseDragged, location: location, windowNumber: windowNumber)
}

func mouseUpEvent(
    location: NSPoint,
    windowNumber: Int,
    modifierFlags: NSEvent.ModifierFlags = [],
    clickCount: Int = 1
) throws -> NSEvent {
    try mouseEvent(
        type: .leftMouseUp,
        location: location,
        windowNumber: windowNumber,
        modifierFlags: modifierFlags,
        clickCount: clickCount
    )
}

func rightMouseDownEvent(location: NSPoint = .zero, windowNumber: Int) throws -> NSEvent {
    try mouseEvent(type: .rightMouseDown, location: location, windowNumber: windowNumber)
}

func rightMouseUpEvent(location: NSPoint = .zero, windowNumber: Int) throws -> NSEvent {
    try mouseEvent(type: .rightMouseUp, location: location, windowNumber: windowNumber)
}

func mouseMovedEvent(location: NSPoint = .zero, windowNumber: Int) throws -> NSEvent {
    try mouseEvent(type: .mouseMoved, location: location, windowNumber: windowNumber)
}

private func mouseEvent(
    type: NSEvent.EventType,
    location: NSPoint = .zero,
    windowNumber: Int,
    modifierFlags: NSEvent.ModifierFlags = [],
    clickCount: Int = 1
) throws -> NSEvent {
    try XCTUnwrap(NSEvent.mouseEvent(
        with: type,
        location: location,
        modifierFlags: modifierFlags,
        timestamp: 0,
        windowNumber: windowNumber,
        context: nil,
        eventNumber: 0,
        clickCount: clickCount,
        pressure: 1
    ))
}

func keyDownEvent(keyCode: UInt16, characters: String) throws -> NSEvent {
    try keyDownEvent(keyCode: keyCode, characters: characters, modifierFlags: [], isARepeat: false)
}

func keyDownEvent(
    keyCode: UInt16,
    characters: String,
    modifierFlags: NSEvent.ModifierFlags,
    isARepeat: Bool = false
) throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifierFlags,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: characters.lowercased(),
        isARepeat: isARepeat,
        keyCode: keyCode
    ))
}

func keyEquivalentEvent(
    keyCode: UInt16,
    characters: String,
    modifierFlags: NSEvent.ModifierFlags
) throws -> NSEvent {
    try keyEquivalentEvent(
        keyCode: keyCode,
        characters: characters,
        modifierFlags: modifierFlags,
        windowNumber: 0
    )
}

func keyEquivalentEvent(
    keyCode: UInt16,
    characters: String,
    modifierFlags: NSEvent.ModifierFlags,
    windowNumber: Int
) throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifierFlags,
        timestamp: 0,
        windowNumber: windowNumber,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: characters.lowercased(),
        isARepeat: false,
        keyCode: keyCode
    ))
}

func commandAEvent() throws -> NSEvent {
    try keyEquivalentEvent(keyCode: 0, characters: "a", modifierFlags: .command)
}

func commandCEvent() throws -> NSEvent {
    try keyEquivalentEvent(keyCode: 8, characters: "c", modifierFlags: .command)
}

func commandXEvent() throws -> NSEvent {
    try keyEquivalentEvent(keyCode: 7, characters: "x", modifierFlags: .command)
}

func commandVEvent() throws -> NSEvent {
    try keyEquivalentEvent(keyCode: 9, characters: "v", modifierFlags: .command)
}

func commandBEvent() throws -> NSEvent {
    try keyEquivalentEvent(keyCode: 11, characters: "b", modifierFlags: .command)
}

func commandIEvent() throws -> NSEvent {
    try keyEquivalentEvent(keyCode: 34, characters: "i", modifierFlags: .command)
}

func commandUEvent() throws -> NSEvent {
    try keyEquivalentEvent(keyCode: 32, characters: "u", modifierFlags: .command)
}

func commandShiftXEvent() throws -> NSEvent {
    try keyEquivalentEvent(keyCode: 7, characters: "X", modifierFlags: [.command, .shift])
}

func commandUpEvent() throws -> NSEvent {
    try keyEquivalentEvent(keyCode: 126, characters: "\u{F700}", modifierFlags: .command)
}

func commandShiftUpEvent() throws -> NSEvent {
    try keyEquivalentEvent(keyCode: 126, characters: "\u{F700}", modifierFlags: [.command, .shift])
}

func commandDownEvent() throws -> NSEvent {
    try keyEquivalentEvent(keyCode: 125, characters: "\u{F701}", modifierFlags: .command)
}

func commandLeftEvent() throws -> NSEvent {
    try keyEquivalentEvent(keyCode: 123, characters: "\u{F702}", modifierFlags: .command)
}

func commandShiftLeftEvent() throws -> NSEvent {
    try keyEquivalentEvent(keyCode: 123, characters: "\u{F702}", modifierFlags: [.command, .shift])
}

func commandRightEvent() throws -> NSEvent {
    try keyEquivalentEvent(keyCode: 124, characters: "\u{F703}", modifierFlags: .command)
}

func commandShiftRightEvent() throws -> NSEvent {
    try keyEquivalentEvent(keyCode: 124, characters: "\u{F703}", modifierFlags: [.command, .shift])
}

func commandShiftDownEvent() throws -> NSEvent {
    try keyEquivalentEvent(keyCode: 125, characters: "\u{F701}", modifierFlags: [.command, .shift])
}

func shiftUpEvent() throws -> NSEvent {
    try keyEquivalentEvent(keyCode: 126, characters: "\u{F700}", modifierFlags: .shift)
}

func shiftDownEvent() throws -> NSEvent {
    try keyEquivalentEvent(keyCode: 125, characters: "\u{F701}", modifierFlags: .shift)
}

func shiftLeftEvent() throws -> NSEvent {
    try keyEquivalentEvent(keyCode: 123, characters: "\u{F702}", modifierFlags: .shift)
}

func shiftRightEvent() throws -> NSEvent {
    try keyEquivalentEvent(keyCode: 124, characters: "\u{F703}", modifierFlags: .shift)
}

func optionLeftEvent(modifierFlags: NSEvent.ModifierFlags = .option) throws -> NSEvent {
    try keyEquivalentEvent(keyCode: 123, characters: "\u{F702}", modifierFlags: modifierFlags)
}

func optionRightEvent(modifierFlags: NSEvent.ModifierFlags = .option) throws -> NSEvent {
    try keyEquivalentEvent(keyCode: 124, characters: "\u{F703}", modifierFlags: modifierFlags)
}

func optionShiftLeftEvent(modifierFlags: NSEvent.ModifierFlags = [.option, .shift]) throws -> NSEvent {
    try keyEquivalentEvent(keyCode: 123, characters: "\u{F702}", modifierFlags: modifierFlags)
}

func optionShiftRightEvent(modifierFlags: NSEvent.ModifierFlags = [.option, .shift]) throws -> NSEvent {
    try keyEquivalentEvent(keyCode: 124, characters: "\u{F703}", modifierFlags: modifierFlags)
}

func plainUpEvent() throws -> NSEvent {
    try keyDownEvent(keyCode: 126, characters: "\u{F700}")
}

func plainDownEvent() throws -> NSEvent {
    try keyDownEvent(keyCode: 125, characters: "\u{F701}")
}

func plainLeftEvent() throws -> NSEvent {
    try keyDownEvent(keyCode: 123, characters: "\u{F702}")
}

func plainRightEvent() throws -> NSEvent {
    try keyDownEvent(keyCode: 124, characters: "\u{F703}")
}

func shiftNumericPadUpEvent() throws -> NSEvent {
    try keyEquivalentEvent(keyCode: 126, characters: "\u{F700}", modifierFlags: [.shift, .numericPad])
}

func shiftNumericPadDownEvent() throws -> NSEvent {
    try keyEquivalentEvent(keyCode: 125, characters: "\u{F701}", modifierFlags: [.shift, .numericPad])
}

func escapeEvent() throws -> NSEvent {
    try keyDownEvent(keyCode: 53, characters: "\u{1B}")
}

@MainActor
func windowLocation(forUTF16Offset offset: Int, in textView: BlockInputTextView) throws -> NSPoint {
    let textContainerX = try XCTUnwrap(textView.blockItem?.textContainerX(forUTF16Offset: offset))
    let textContainerOrigin = textView.textContainerOrigin
    if let window = textView.window {
        let caretRect = textView.firstRect(forCharacterRange: NSRange(location: offset, length: 0), actualRange: nil)
        if caretRect != .zero, !caretRect.isNull, !caretRect.isInfinite {
            let windowPoint = window.convertPoint(fromScreen: caretRect.origin)
            return NSPoint(x: windowPoint.x, y: windowPoint.y + 4)
        }
    }
    return textView.convert(
        NSPoint(x: textContainerOrigin.x + textContainerX, y: textContainerOrigin.y + 8),
        to: nil
    )
}

func commandZEvent() throws -> NSEvent {
    try keyEquivalentEvent(keyCode: 6, characters: "z", modifierFlags: .command)
}

func commandShiftZEvent() throws -> NSEvent {
    try keyEquivalentEvent(keyCode: 6, characters: "Z", modifierFlags: [.command, .shift])
}
