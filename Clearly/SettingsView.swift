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
    @AppStorage("editorFontSize") private var fontSize: Double = 12
    @AppStorage("previewFontFamily") private var previewFontFamily = "sanFrancisco"
    @AppStorage("themePreference") private var themePreference = "system"
    @AppStorage("launchBehavior") private var launchBehavior = "lastFile"
    @AppStorage("contentWidth") private var contentWidth = "off"
    @AppStorage("hideFrontmatterInPreview") private var hideFrontmatterInPreview = false

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            commandLineSettings
                .tabItem {
                    Label("Command Line", systemImage: "terminal")
                }

            aboutView
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 460)
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

    // MARK: - Command Line Settings

    @State private var mcpCopied = false
    @State private var cliSymlinkState: CLIInstaller.State = CLIInstaller.symlinkState()
    @State private var cliInstallBusy = false
    @State private var cliInstallError: String?

    private var bundledCLIBinaryPath: String? {
        CLIInstaller.bundledBinaryURL()?.path
    }

    private var cliBundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.sabotage.clearly"
    }

    private var cliBundledExecutable: Bool {
        guard let path = bundledCLIBinaryPath else { return false }
        return FileManager.default.isExecutableFile(atPath: path)
    }

    private var commandLineSettings: some View {
        Form {
            // Row 1 — bundled binary status
            HStack {
                Text("Helper binary")
                Spacer()
                if cliBundledExecutable {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Bundled")
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("Missing — reinstall Clearly")
                        .foregroundStyle(.secondary)
                }
            }

            // Row 2 — terminal install
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Terminal command")
                    Spacer()
                    switch cliSymlinkState {
                    case .installed:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Installed at \(CLIInstaller.symlinkPath)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .installedElsewhere:
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Different `clearly` on PATH")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .notInstalled:
                        Image(systemName: "circle")
                            .foregroundStyle(.secondary)
                        Text("Not installed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    switch cliSymlinkState {
                    case .installed:
                        Button("Uninstall") {
                            Task { await runUninstall() }
                        }
                        .disabled(cliInstallBusy)
                    case .installedElsewhere:
                        Button("Install \u{2026}") {}
                            .disabled(true)
                        Text("Remove the existing `clearly` from /usr/local/bin manually before installing.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    case .notInstalled:
                        Button("Install \u{2026}") {
                            Task { await runInstall() }
                        }
                        .disabled(cliInstallBusy || !cliBundledExecutable)
                    }
                    Spacer()
                }

                if let errorText = cliInstallError {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text("Opens Terminal and runs `sudo ln -sf` so `clearly` resolves on your shell PATH. Enter your admin password in Terminal when prompted, then switch back here — Clearly detects the install automatically.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Row 3 — MCP config copy
            VStack(alignment: .leading, spacing: 8) {
                Button(mcpCopied ? "Copied!" : "Copy MCP Config") {
                    copyMCPConfig()
                }
                .disabled(!cliBundledExecutable)

                Text("The MCP server lets AI agents search your notes, explore backlinks, and browse tags. Copy this config into any MCP-compatible app (Claude Desktop, Cursor, Windsurf, etc.).")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            cliSymlinkState = CLIInstaller.symlinkState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            cliSymlinkState = CLIInstaller.symlinkState()
        }
    }

    private func runInstall() async {
        cliInstallBusy = true
        cliInstallError = nil
        defer { cliInstallBusy = false }
        do {
            try await CLIInstaller.install()
            cliSymlinkState = CLIInstaller.symlinkState()
        } catch {
            cliInstallError = error.localizedDescription
        }
    }

    private func runUninstall() async {
        cliInstallBusy = true
        cliInstallError = nil
        defer { cliInstallBusy = false }
        do {
            try await CLIInstaller.uninstall()
            cliSymlinkState = CLIInstaller.symlinkState()
        } catch {
            cliInstallError = error.localizedDescription
        }
    }

    private func copyMCPConfig() {
        let command: String
        if case .installed = cliSymlinkState {
            command = CLIInstaller.symlinkPath
        } else if let path = bundledCLIBinaryPath {
            command = path
        } else {
            return
        }
        let config = """
        {
          "mcpServers": {
            "clearly": {
              "command": "\(command)",
              "args": ["mcp", "--bundle-id", "\(cliBundleIdentifier)"]
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
                #if canImport(Sparkle) && !DEBUG
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
