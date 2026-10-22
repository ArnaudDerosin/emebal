import AppKit
import Foundation
import Testing
@preconcurrency import Translation
@testable import Emebal

@MainActor
@Suite("TranslationModel")
struct TranslationModelTests {
    @Test("Asking again for the same languages still reruns Apple's translation")
    func sameLanguagesRerun() {
        let model = TranslationModel(text: "こんにちは", settings: .shared)
        let japanese = Locale.Language(identifier: "ja")
        let english = Locale.Language(identifier: "en")

        model.requestAppleTranslation(from: japanese, to: english)
        let first = model.appleConfiguration
        // Back to the same languages, e.g. after trying another target.
        model.requestAppleTranslation(from: japanese, to: english)
        // .translationTask only runs again when the configuration changes.
        #expect(model.appleConfiguration != first)
        #expect(model.appleConfiguration?.target == english)

        model.requestAppleTranslation(from: japanese, to: Locale.Language(identifier: "fr"))
        #expect(model.appleConfiguration?.target == Locale.Language(identifier: "fr"))
    }

    @Test("Ignores a result from an earlier request")
    func ignoresStaleResults() {
        let model = TranslationModel(text: "こんにちは", settings: .shared)
        let current = model.appleRequest
        model.setAppleState(.done("Hello"), for: current)
        #expect(model.appleState == .done("Hello"))
        model.setAppleState(.done("Bonjour"), for: current - 1)
        #expect(model.appleState == .done("Hello"))
    }
}

@MainActor
@Suite("TranslationPanel")
struct TranslationPanelTests {
    // A screen's usable area: x 0–1700, y 80 (above the Dock) to 1000 (below the menu bar).
    let visible = NSRect(x: 0, y: 80, width: 1700, height: 920)

    @Test("Moves a panel that grew under the Dock back up")
    func belowTheDock() {
        let frame = NSRect(x: 300, y: 20, width: 520, height: 500)
        #expect(TranslationPanel.origin(keeping: frame, inside: visible) == NSPoint(x: 300, y: 88))
    }

    @Test("Moves a panel past the right or top edge back in")
    func otherEdges() {
        let right = NSRect(x: 1500, y: 400, width: 520, height: 300)
        #expect(TranslationPanel.origin(keeping: right, inside: visible).x == CGFloat(1700 - 8 - 520))
        let top = NSRect(x: 100, y: 800, width: 520, height: 300)
        #expect(TranslationPanel.origin(keeping: top, inside: visible).y == CGFloat(1000 - 8 - 300))
    }

    @Test("Leaves a panel that fits where it is")
    func fits() {
        let frame = NSRect(x: 300, y: 300, width: 520, height: 300)
        #expect(TranslationPanel.origin(keeping: frame, inside: visible) == frame.origin)
    }

    @Test("Keeps the top on screen when the panel is taller than the space")
    func tallerThanTheScreen() {
        let frame = NSRect(x: 300, y: 0, width: 520, height: 1200)
        let origin = TranslationPanel.origin(keeping: frame, inside: visible)
        #expect(origin.y + frame.height == CGFloat(1000 - 8))
    }
}
