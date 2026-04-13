import Foundation

extension Notification.Name {
    static let appLanguageDidChange = Notification.Name("appLanguageDidChange")
}

enum AppLanguage: String, CaseIterable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case spanish = "es"
    case russian = "ru"
    case french = "fr"
    case german = "de"
    case italian = "it"

    static var supportedIdentifiers: [String] {
        allCases.map(\.rawValue)
    }

    static func preferredLocalization(for preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        Bundle.preferredLocalizations(
            from: supportedIdentifiers,
            forPreferences: preferredLanguages
        ).first ?? english.rawValue
    }

    static func bundle(for localization: String) -> Bundle {
        guard let path = Bundle.main.path(forResource: localization, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }

    static func currentLocalization() -> String {
        AppLanguagePreference.current.localeIdentifier
    }
}

enum AppLanguagePreference: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case spanish = "es"
    case russian = "ru"
    case french = "fr"
    case german = "de"
    case italian = "it"

    static let userDefaultsKey = "appLanguagePreference"
    static let appliedUserDefaultsKey = "appliedAppLanguagePreference"

    var id: String { rawValue }

    static var current: AppLanguagePreference {
        let storedValue = UserDefaults.standard.string(forKey: userDefaultsKey) ?? system.rawValue
        return AppLanguagePreference(rawValue: storedValue) ?? .system
    }

    static var applied: AppLanguagePreference {
        let storedValue = UserDefaults.standard.string(forKey: appliedUserDefaultsKey) ?? system.rawValue
        return AppLanguagePreference(rawValue: storedValue) ?? .system
    }

    static var hasPendingChange: Bool {
        current != applied
    }

    var localeIdentifier: String {
        switch self {
        case .system:
            return AppLanguage.preferredLocalization()
        case .english:
            return AppLanguage.english.rawValue
        case .simplifiedChinese:
            return AppLanguage.simplifiedChinese.rawValue
        case .traditionalChinese:
            return AppLanguage.traditionalChinese.rawValue
        case .japanese:
            return AppLanguage.japanese.rawValue
        case .korean:
            return AppLanguage.korean.rawValue
        case .spanish:
            return AppLanguage.spanish.rawValue
        case .russian:
            return AppLanguage.russian.rawValue
        case .french:
            return AppLanguage.french.rawValue
        case .german:
            return AppLanguage.german.rawValue
        case .italian:
            return AppLanguage.italian.rawValue
        }
    }

    var titleKey: String {
        switch self {
        case .system:
            return "settings.general.language.system"
        case .english:
            return "settings.general.language.english"
        case .simplifiedChinese:
            return "settings.general.language.simplifiedChinese"
        case .traditionalChinese:
            return "settings.general.language.traditionalChinese"
        case .japanese:
            return "settings.general.language.japanese"
        case .korean:
            return "settings.general.language.korean"
        case .spanish:
            return "settings.general.language.spanish"
        case .russian:
            return "settings.general.language.russian"
        case .french:
            return "settings.general.language.french"
        case .german:
            return "settings.general.language.german"
        case .italian:
            return "settings.general.language.italian"
        }
    }

    static func configureDefaultPreference() {
        UserDefaults.standard.register(defaults: [
            userDefaultsKey: system.rawValue
        ])
    }
}

enum L10n {
    static func string(_ key: String, defaultValue: String, comment: String = "") -> String {
        string(
            key,
            defaultValue: defaultValue,
            localization: AppLanguage.currentLocalization(),
            comment: comment
        )
    }

    static func string(_ key: String, defaultValue: String, localization: String, comment: String = "") -> String {
        NSLocalizedString(
            key,
            tableName: nil,
            bundle: AppLanguage.bundle(for: localization),
            value: defaultValue,
            comment: comment
        )
    }

    static func format(_ key: String, defaultValue: String, _ arguments: CVarArg..., comment: String = "") -> String {
        let format = string(key, defaultValue: defaultValue, comment: comment)
        return String(format: format, locale: Locale(identifier: AppLanguage.currentLocalization()), arguments: arguments)
    }
}
