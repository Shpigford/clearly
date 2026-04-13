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
    @AppStorage(TypographyPreferences.editorFontNameKey) private var editorFontName = ""
    @AppStorage(TypographyPreferences.previewFontNameKey) private var previewFontName = ""
    @AppStorage("themePreference") private var themePreference = "system"
    @AppStorage("launchBehavior") private var launchBehavior = "lastFile"

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            aboutView
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 460, height: 440)
    }

    @StateObject private var fontPanelController = TypographyFontPanelController()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var selectedEditorFontName: String? {
        editorFontName.isEmpty ? nil : editorFontName
    }

    private var selectedPreviewFontName: String? {
        previewFontName.isEmpty ? nil : previewFontName
    }

    private var editorFontChoices: [EditorFontChoice] {
        TypographyPreferences.editorFontChoices()
    }

    private var editorFontSelection: Binding<String> {
        Binding(
            get: {
                guard let selectedEditorFontName,
                      editorFontChoices.contains(where: { $0.storedFontName == selectedEditorFontName }) else {
                    return TypographyPreferences.defaultEditorFontChoiceID
                }

                return selectedEditorFontName
            },
            set: { newValue in
                editorFontName = newValue == TypographyPreferences.defaultEditorFontChoiceID ? "" : newValue
            }
        )
    }

    private var generalSettings: some View {
        Form {
            Section {
                Picker("Appearance", selection: $themePreference) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }

                Picker("On Launch", selection: $launchBehavior) {
                    Text("Open last file").tag("lastFile")
                    Text("Create new document").tag("newDocument")
                }
            }

            Section("Typography") {
                Picker("Editor Font", selection: editorFontSelection) {
                    ForEach(editorFontChoices) { choice in
                        Text(choice.displayName).tag(choice.id)
                    }
                }

                HStack {
                    Text("Preview Font")
                    Spacer()
                    Text(TypographyPreferences.displayName(for: .preview, size: CGFloat(fontSize), storedFontName: selectedPreviewFontName))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Choose Preview Font…") {
                        fontPanelController.chooseFont(for: .preview, size: CGFloat(fontSize), storedFontName: selectedPreviewFontName)
                    }

                    Button("Reset") {
                        TypographyPreferences.clearStoredFontName(for: .preview)
                    }
                    .disabled(selectedPreviewFontName == nil)
                }

                HStack {
                    Text("Font Size")
                    Slider(value: $fontSize, in: 12...24, step: 1)
                    Text("\(Int(fontSize))")
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .frame(width: 30, alignment: .trailing)
                }

                Text("Preview uses the current font size setting. Quick Look stays on the bundled default preview font.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                KeyboardShortcuts.Recorder("New Scratchpad:", name: .newScratchpad)
                Toggle("Launch at Login", isOn: $launchAtLogin)
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

            Text("Version \(appVersion)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("A clean, native markdown editor for Mac.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                #if canImport(Sparkle)
                Button("Check for Updates") {
                    updater.checkForUpdates()
                }
                .buttonStyle(.bordered)
                #endif

                Button("Website") {
                    NSWorkspace.shared.open(URL(string: "https://clearly.md")!)
                }
                .buttonStyle(.bordered)

                Button("GitHub") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/Shpigford/clearly")!)
                }
                .buttonStyle(.bordered)
            }

            Text("Free and open source under the MIT License.")
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
}
