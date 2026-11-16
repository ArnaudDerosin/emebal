import Testing
@testable import Emebal

@Suite("Romaji")
struct RomajiTests {
    @Test("Reads Japanese the way Google Translate shows it", arguments: [
        ("東京に行きたいです。", "Tōkyō ni ikitai desu."),
        ("私は学校へ行きます", "Watashi wa gakkō e ikimasu"),
        ("ケーキを作って", "Kēki o tsukutte"),
        ("食べられなかった。", "Taberarenakatta."),
        ("ちょっと待って", "Chotto matte"),
        ("本を読んで、お金がない！", "Hon o yonde, okane ga nai!"),
        ("「こんにちは」と言った", "\"Kon'nichiwa\" to itta"),
        ("思う", "Omou"),
        ("iOS 26以降", "iOS 26 ikō"),
    ])
    func readings(text: String, expected: String) {
        #expect(Romaji.of(text) == expected)
    }

    @Test("Leaves code and English as written, and keeps line breaks")
    func mixed() {
        #expect(Romaji.of("このPRで`sendEvent()`を修正しました\n明日") == "Kono PR de `sendEvent()` o shūsei shimashita\nAsu")
    }

    @Test("Nothing for text without Japanese")
    func notJapanese() {
        #expect(Romaji.of("Hello, world") == nil)
    }
}
