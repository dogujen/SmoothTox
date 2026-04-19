import Foundation

struct AppLocalizer {
    static let shared = AppLocalizer()

    private let activeStrings: [String: String]
    private let fallbackStrings: [String: String]

    private init() {
        fallbackStrings = Self.loadStrings(for: "en")

        let localeLanguage = Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
        let selectedLanguage = localeLanguage.hasPrefix("tr") ? "tr" : "en"

        activeStrings = Self.loadStrings(for: selectedLanguage)
    }

    func text(_ key: String) -> String {
        activeStrings[key] ?? fallbackStrings[key] ?? key
    }

    func format(_ key: String, _ arguments: CVarArg...) -> String {
        let format = text(key)
        return String(format: format, locale: Locale.current, arguments: arguments)
    }

    private static func loadStrings(for languageCode: String) -> [String: String] {
        let urls: [URL?] = [
            Bundle.module.url(forResource: languageCode, withExtension: "json", subdirectory: "i18n"),
            Bundle.module.url(forResource: languageCode, withExtension: "json")
        ]

        for url in urls {
            guard let url,
                  let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
                continue
            }
            return json
        }

        return [:]
    }
}
