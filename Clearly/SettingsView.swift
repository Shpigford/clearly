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
    @AppStorage("themePreference") private var themePreference = "system"
    @AppStorage("launchBehavior") private var launchBehavior = "lastFile"

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            mcpSettings
                .tabItem {
                    Label("MCP", systemImage: "network")
                }

            aboutView
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var generalSettings: some View {
        Form {
            Picker("Appearance", selection: $themePreference) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            Picker("On Launch", selection: $launchBehavior) {
                Text("Open last file").tag("lastFile")
                Text("Create new document").tag("newDocument")
            }
            HStack {
                Text("Font Size")
                Slider(value: $fontSize, in: 12...24, step: 1)
                Text("\(Int(fontSize))")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .frame(width: 30, alignment: .trailing)
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
    }

    // MARK: - MCP Settings

    @State private var mcpCopied = false

    private var mcpBinaryPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Clearly/ClearlyMCP").path
    }

    private var mcpBundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.sabotage.clearly"
    }

    private var mcpBinaryInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: mcpBinaryPath)
    }

    private var mcpSettings: some View {
        Form {
            // Status
            HStack {
                Text("MCP Helper")
                Spacer()
                if mcpBinaryInstalled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Installed")
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("Not Installed")
                        .foregroundStyle(.secondary)
                }
            }

            // Copy config
            Button(mcpCopied ? "Copied!" : "Copy MCP Config") {
                copyMCPConfig()
            }

            // Help text
            Text("The MCP server lets AI agents search your notes, explore backlinks, and browse tags. It automatically discovers all your vaults. Copy the config and add it to any MCP-compatible app (Claude Desktop, Cursor, Windsurf, etc.).")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .formStyle(.grouped)
    }

    private func copyMCPConfig() {
        let config = """
        {
          "mcpServers": {
            "clearly": {
              "command": "\(mcpBinaryPath)",
              "args": ["--bundle-id", "\(mcpBundleIdentifier)"]
            }
          }
        }
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(config, forType: .string)
        mcpCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            mcpCopied = false
        }
    }

    // MARK: - About

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
