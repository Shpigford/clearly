import SwiftUI
import ClearlyCore
import KeyboardShortcuts
import ServiceManagement
#if canImport(Sparkle)
import Sparkle
#endif

struct SettingsView: View {
    #if canImport(Sparkle)
    let updater: SPUUpdater
    #endif

    @AppStorage("editorFontSize") private var fontSize: Double = 12
    @AppStorage("previewFontFamily") private var previewFontFamily = "sanFrancisco"
    @AppStorage("themePreference") private var themePreference = "system"
    @AppStorage("contentWidth") private var contentWidth = "off"
    @AppStorage("hideFrontmatterInPreview") private var hideFrontmatterInPreview = false
    @AppStorage("keepRunningMenubarOnly") private var keepRunningMenubarOnly = true
    @AppStorage("launchBehavior") private var launchBehavior = "filePicker"
    @AppStorage("defaultViewMode") private var defaultViewMode = "edit"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .background(SettingsWindowObserver())
        .background {
            Button("") { dismiss() }
                .keyboardShortcut("w", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private var generalSettings: some View {
        Form {
            Picker("Appearance", selection: $themePreference) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }

            Picker("On Launch", selection: $launchBehavior) {
                Text("Create new document").tag("newDocument")
                Text("Open last file").tag("lastFile")
                Text("Show file picker").tag("filePicker")
                Text("Do nothing").tag("nothing")
            }

            Picker("Default View Mode", selection: $defaultViewMode) {
                Text("Editor").tag("edit")
                Text("Preview").tag("preview")
            }

            HStack {
                Text("Font Size")
                Slider(value: $fontSize, in: 12...24, step: 1)
                Text("\(Int(fontSize))")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .frame(width: 30, alignment: .trailing)
            }

            Picker("Preview Font", selection: $previewFontFamily) {
                Text("San Francisco").tag("sanFrancisco")
                Text("New York").tag("newYork")
                Text("SF Mono").tag("sfMono")
            }

            Picker("Content Width", selection: $contentWidth) {
                Text("Off").tag("off")
                Text("Narrow").tag("narrow")
                Text("Medium").tag("medium")
                Text("Wide").tag("wide")
            }

            Toggle("Hide frontmatter in Preview", isOn: $hideFrontmatterInPreview)
            Toggle("Keep running in menu bar", isOn: $keepRunningMenubarOnly)
                .onChange(of: keepRunningMenubarOnly) { _, _ in
                    ClearlyAppDelegate.shared?.updateActivationPolicy()
                }

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
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

private struct AboutView: View {
    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }
    private var build: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?"
    }

    var body: some View {
        VStack(spacing: 12) {
            if let icon = NSImage(named: "AppIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 96, height: 96)
            }
            Text("Clearly")
                .font(.title2.weight(.semibold))
            Text("Version \(version) (\(build))")
                .font(.callout)
                .foregroundStyle(.secondary)
            Divider()
                .padding(.horizontal, 60)
            VStack(spacing: 4) {
                Link("Website", destination: URL(string: "https://clearly.md")!)
                Link("Changelog", destination: URL(string: "https://clearly.md/changelog")!)
                Link("Report a Bug", destination: URL(string: "https://github.com/Shpigford/clearly/issues")!)
            }
            .font(.callout)
            Text("© Sabotage Media")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 24)
    }
}
