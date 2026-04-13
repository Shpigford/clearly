import SwiftUI
import KeyboardShortcuts
import ServiceManagement
#if canImport(Sparkle)
import Sparkle
#endif

struct SettingsView: View {
    #if canImport(Sparkle)
    let updater: SPUUpdater
    #endif
    @AppStorage("editorFontSize") private var fontSize: Double = 16
    @AppStorage(AppLanguagePreference.userDefaultsKey) private var appLanguagePreference = AppLanguagePreference.system.rawValue
    @AppStorage(AppLanguagePreference.appliedUserDefaultsKey) private var appliedLanguagePreference = AppLanguagePreference.system.rawValue
    @AppStorage("themePreference") private var themePreference = "system"
    @AppStorage("launchBehavior") private var launchBehavior = "lastFile"

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label(L10n.string("settings.tab.general", defaultValue: "General"), systemImage: "gearshape")
                }

            aboutView
                .tabItem {
                    Label(L10n.string("settings.tab.about", defaultValue: "About"), systemImage: "info.circle")
                }
        }
        .frame(width: 420, height: 360)
    }

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var hasPendingLanguageRestart: Bool {
        appLanguagePreference != appliedLanguagePreference
    }

    private var generalSettings: some View {
        Form {
            VStack(alignment: .leading, spacing: 6) {
                Picker(L10n.string("settings.general.language", defaultValue: "Language"), selection: $appLanguagePreference) {
                    ForEach(AppLanguagePreference.allCases) { language in
                        Text(languageOptionTitle(for: language)).tag(language.rawValue)
                    }
                }
                .onChange(of: appLanguagePreference) { oldValue, newValue in
                    guard newValue != oldValue else { return }
                    guard newValue != appliedLanguagePreference else { return }
                    presentLanguageRestartPrompt()
                }
                Text(L10n.string("settings.general.language.restartHint", defaultValue: "Language changes take effect after restarting Clearly."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if hasPendingLanguageRestart {
                    HStack(spacing: 10) {
                        Text(L10n.string("settings.general.language.restartPending", defaultValue: "Your language change is ready to apply."))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button(L10n.string("settings.general.language.restartNow", defaultValue: "Quit and Reopen Now")) {
                            AppRelauncher.relaunchIfPossible()
                        }
                        .buttonStyle(.link)
                    }
                }
            }
            Picker(L10n.string("settings.general.appearance", defaultValue: "Appearance"), selection: $themePreference) {
                Text(L10n.string("settings.general.appearance.system", defaultValue: "System")).tag("system")
                Text(L10n.string("settings.general.appearance.light", defaultValue: "Light")).tag("light")
                Text(L10n.string("settings.general.appearance.dark", defaultValue: "Dark")).tag("dark")
            }
            Picker(L10n.string("settings.general.onLaunch", defaultValue: "On Launch"), selection: $launchBehavior) {
                Text(L10n.string("settings.general.launch.lastFile", defaultValue: "Open last file")).tag("lastFile")
                Text(L10n.string("settings.general.launch.newDocument", defaultValue: "Create new document")).tag("newDocument")
            }
            HStack {
                Text(L10n.string("settings.general.fontSize", defaultValue: "Font Size"))
                Slider(value: $fontSize, in: 12...24, step: 1)
                Text("\(Int(fontSize))")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .frame(width: 30, alignment: .trailing)
            }
            KeyboardShortcuts.Recorder(L10n.string("settings.general.newScratchpad", defaultValue: "New Scratchpad:"), name: .newScratchpad)
            Toggle(L10n.string("settings.general.launchAtLogin", defaultValue: "Launch at Login"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
        }
        .formStyle(.grouped)
    }

    private var aboutView: some View {
        VStack(spacing: 16) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
            }

            Text("Clearly")
                .font(.system(size: 24, weight: .semibold))

            Text(L10n.format("settings.about.version", defaultValue: "Version %@", appVersion))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(L10n.string("settings.about.description", defaultValue: "A clean, native markdown editor for Mac."))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                #if canImport(Sparkle)
                Button(L10n.string("settings.about.checkForUpdates", defaultValue: "Check for Updates")) {
                    updater.checkForUpdates()
                }
                .buttonStyle(.bordered)
                #endif

                Button(L10n.string("settings.about.website", defaultValue: "Website")) {
                    NSWorkspace.shared.open(URL(string: "https://clearly.md")!)
                }
                .buttonStyle(.bordered)

                Button(L10n.string("settings.about.github", defaultValue: "GitHub")) {
                    NSWorkspace.shared.open(URL(string: "https://github.com/Shpigford/clearly")!)
                }
                .buttonStyle(.bordered)
            }

            Text(L10n.string("settings.about.license", defaultValue: "Free and open source under the MIT License."))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private func presentLanguageRestartPrompt() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.string(
            "settings.general.language.restartPrompt.title",
            defaultValue: "Restart Clearly Now?"
        )
        alert.informativeText = L10n.string(
            "settings.general.language.restartPrompt.message",
            defaultValue: "Apply the new language by quitting and reopening Clearly now."
        )
        alert.addButton(withTitle: L10n.string(
            "settings.general.language.restartNow",
            defaultValue: "Quit and Reopen Now"
        ))
        alert.addButton(withTitle: L10n.string(
            "settings.general.language.restartLater",
            defaultValue: "Later"
        ))

        if alert.runModal() == .alertFirstButtonReturn {
            AppRelauncher.relaunchIfPossible()
        }
    }

    private func languageOptionTitle(for language: AppLanguagePreference) -> String {
        if language == .system {
            return L10n.string(
                language.titleKey,
                defaultValue: language.rawValue,
                localization: AppLanguage.preferredLocalization()
            )
        }

        return L10n.string(language.titleKey, defaultValue: language.rawValue)
    }
}
