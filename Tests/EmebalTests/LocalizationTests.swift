import Foundation
import Testing

/// Checks every translation against the English strings, which
/// scripts/update-strings.sh generates from the code.
@Suite("Localization")
struct LocalizationTests {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("../../Resources/Localization")
        .standardized

    static var languages: [String] {
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return folders.filter { $0.hasSuffix(".lproj") && $0 != "en.lproj" }.sorted()
    }

    static func strings(_ folder: String) throws -> [String: String] {
        let url = directory.appendingPathComponent(folder).appendingPathComponent("Localizable.strings")
        let data = try Data(contentsOf: url)
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    }

    /// "%@", "%lld" or "%2$@", without the position, so reordering is allowed.
    static func placeholders(_ text: String) -> [String] {
        let pattern = /%(?:\d+\$)?([@a-z]+)/
        return text.matches(of: pattern).map { String($0.output.1) }.sorted()
    }

    @Test("There is at least one translation")
    func hasTranslations() {
        #expect(!Self.languages.isEmpty)
    }

    @Test("Each translation has exactly the English keys, with the same placeholders", arguments: languages)
    func matchesEnglish(_ folder: String) throws {
        let english = try Self.strings("en.lproj")
        let translation = try Self.strings(folder)
        #expect(Set(translation.keys).subtracting(english.keys).isEmpty, "Keys no longer used in \(folder)")
        #expect(Set(english.keys).subtracting(translation.keys).isEmpty, "Keys missing in \(folder)")
        for (key, value) in translation where english[key] != nil {
            #expect(Self.placeholders(value) == Self.placeholders(key), "Placeholders differ in \(folder): \(key)")
            #expect(!value.trimmingCharacters(in: .whitespaces).isEmpty || key.trimmingCharacters(in: .whitespaces).isEmpty,
                    "Empty translation in \(folder): \(key)")
        }
    }
}
