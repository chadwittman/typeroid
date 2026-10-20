import Foundation
import Testing
@testable import TypeRoidCore

@Test func upArrowCannotStartTheMicrophone() {
    var filter = GlobeKeyFilter()
    let up = Int64(0x7E)

    #expect(filter.poll(globeDown: true, otherFunctionKeyDown: false, at: 1) == .none)
    #expect(filter.poll(globeDown: true, otherFunctionKeyDown: true, at: 1.01) == .void)
    #expect(filter.key(code: up, isDown: true, at: 2) == .void)
    #expect(filter.key(code: FunctionFlag.globeKeyCode, isDown: true, at: 2.1) == .void)
    #expect(filter.poll(globeDown: true, otherFunctionKeyDown: false, at: 2.2) == .none)

    #expect(filter.key(code: FunctionFlag.globeKeyCode, isDown: true, at: 3) == .globeDown)
    #expect(filter.poll(globeDown: true, otherFunctionKeyDown: false, at: 3.2) == .none)
    #expect(filter.poll(globeDown: false, otherFunctionKeyDown: false, at: 3.4) == .globeUp)

    var gesture = FunctionDictationGesture()
    _ = gesture.fnDown(at: 4)
    _ = gesture.fnUp(at: 4.05)
    #expect(gesture.fnDown(at: 4.2) == [.begin(.handsFree)])
    #expect(gesture.voidRecentPress(at: 4.25) == [.discard])
    #expect(gesture.phase == .idle)
}

@Test func functionHoldStartsPushToTalkAndReleaseEnds() {
    var gesture = FunctionDictationGesture()

    #expect(gesture.fnDown(at: 10).isEmpty)
    #expect(gesture.holdElapsed(at: 10.22) == [.begin(.pushToTalk)])
    #expect(gesture.fnUp(at: 11.4) == [.end])
    #expect(gesture.phase == .idle)
}

@Test func functionShortTapAsksForAHold() {
    var gesture = FunctionDictationGesture()

    #expect(gesture.fnDown(at: 1).isEmpty)
    #expect(gesture.fnUp(at: 1.08).isEmpty)
    #expect(gesture.secondTapWindowElapsed(at: 1.53) == [.hintHold])
    #expect(gesture.phase == .idle)
}

@Test func functionDoubleTapStartsHandsFreeUntilLaterPress() {
    var gesture = FunctionDictationGesture()

    #expect(gesture.fnDown(at: 5).isEmpty)
    #expect(gesture.fnUp(at: 5.09).isEmpty)
    #expect(gesture.fnDown(at: 5.28) == [.begin(.handsFree)])
    #expect(gesture.phase == .handsFreeHeld(startedAt: 5.28))
    #expect(gesture.fnDown(at: 5.3).isEmpty)
    #expect(gesture.fnUp(at: 5.36).isEmpty)
    #expect(gesture.phase == .handsFree(startedAt: 5.28))
    #expect(gesture.fnDown(at: 8) == [.end])
    #expect(gesture.phase == .idle)
}

@Test func functionNextPressAfterHandsFreeStops() {
    var gesture = FunctionDictationGesture()

    _ = gesture.fnDown(at: 2)
    _ = gesture.fnUp(at: 2.07)
    #expect(gesture.fnDown(at: 2.2) == [.begin(.handsFree)])
    #expect(gesture.fnDown(at: 2.4).isEmpty)
    #expect(gesture.fnUp(at: 2.45).isEmpty)
    #expect(gesture.fnDown(at: 2.6) == [.end])
    #expect(gesture.phase == .idle)
}

@Test func functionReleaseBeforeTapCeilingKeepsRecordingForASecondTap() {
    var gesture = FunctionDictationGesture()

    _ = gesture.fnDown(at: 0)
    #expect(gesture.holdElapsed(at: 0.22) == [.begin(.pushToTalk)])
    #expect(gesture.fnUp(at: 0.35).isEmpty)
    #expect(gesture.phase == .armingDoubleTap(upAt: 0.35, recording: true))
    #expect(gesture.fnDown(at: 0.55) == [.promoteToHandsFree])
    #expect(gesture.fnUp(at: 0.62).isEmpty)
    #expect(gesture.fnDown(at: 2) == [.end])
}

@Test func functionAbandonedEarlyHoldDiscardsThenHints() {
    var gesture = FunctionDictationGesture()

    _ = gesture.fnDown(at: 0)
    _ = gesture.holdElapsed(at: 0.22)
    _ = gesture.fnUp(at: 0.3)
    #expect(gesture.secondTapWindowElapsed(at: 0.75) == [.discard, .hintHold])
    #expect(gesture.phase == .idle)
}

@Test func functionChordBeforeHoldDoesNotDictate() {
    var gesture = FunctionDictationGesture()

    _ = gesture.fnDown(at: 4)
    #expect(gesture.otherKey(at: 4.05).isEmpty)
    #expect(gesture.phase == .idle)
    #expect(gesture.holdElapsed(at: 4.3).isEmpty)
}

@Test func functionChordJustAfterHoldStartsDiscards() {
    var gesture = FunctionDictationGesture()

    _ = gesture.fnDown(at: 4)
    #expect(gesture.holdElapsed(at: 4.22) == [.begin(.pushToTalk)])
    #expect(gesture.otherKey(at: 4.3) == [.discard])
    #expect(gesture.phase == .idle)
}

@Test func functionOtherKeyDuringEstablishedHoldDoesNotStop() {
    var gesture = FunctionDictationGesture()

    _ = gesture.fnDown(at: 1)
    _ = gesture.holdElapsed(at: 1.22)
    #expect(gesture.otherKey(at: 2).isEmpty)
    #expect(gesture.phase == .pushToTalk(downAt: 1))
    #expect(gesture.fnUp(at: 2.4) == [.end])
}

@Test func lateCopyOfTheFirstFnPressDoesNotCancelTheDoubleTap() {
    var signals = FunctionKeySignals()
    var gesture = FunctionDictationGesture()

    func feed(down: Bool, at time: TimeInterval) {
        guard let edge = signals.edge(down: down, at: time) else { return }
        switch edge {
        case .down(let time):
            _ = gesture.fnDown(at: time)
        case .up(let time):
            _ = gesture.fnUp(at: time)
        case .otherKey, .escape:
            break
        }
    }

    feed(down: true, at: 1)
    feed(down: false, at: 1.08)
    feed(down: true, at: 1)
    feed(down: false, at: 1.08)
    feed(down: true, at: 1.3)
    #expect(gesture.phase == .handsFreeHeld(startedAt: 1.3))
    feed(down: false, at: 1.38)
    #expect(gesture.phase == .handsFree(startedAt: 1.3))
}
