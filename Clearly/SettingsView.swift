import SwiftUI
import ClearlyCore
import Combine
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
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("sidebarSize") private var sidebarSize: String = "medium"

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            SyncSettingsTab()
                .tabItem {
                    Label("Sync", systemImage: "icloud")
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
        .background(SettingsWindowObserver())
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
            Picker("Sidebar Size", selection: $sidebarSize) {
                Text("Small").tag("small")
                Text("Medium").tag("medium")
                Text("Large").tag("large")
                Text("X-Large").tag("xlarge")
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
            Toggle("Show icon in menu bar", isOn: $showMenuBarIcon)
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
    @State private var cliInstallError: CLIInstaller.CLIInstallerError?
    @State private var cliCommandCopied = false
    @State private var cliDetailsCopied = false
    @State private var cliErrorDetailsExpanded = false

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

            // Row 2 — install
            VStack(alignment: .leading, spacing: 8) {
                cliStatusHeader
                cliInstallUI
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

    @ViewBuilder
    private var cliStatusHeader: some View {
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
    }

    @ViewBuilder
    private var cliInstallUI: some View {
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

        if let error = cliInstallError {
            cliErrorPanel(error)
        }

        Text("Opens Terminal and runs `sudo ln -sf` so `clearly` resolves on your shell PATH. Enter your admin password in Terminal when prompted, then switch back here — Clearly detects the install automatically.")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private func cliErrorPanel(_ error: CLIInstaller.CLIInstallerError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(error.errorDescription ?? "Install failed.")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if case .terminalAutomationDenied = error {
                    Button("Open Privacy Settings") { openPrivacySettings() }
                        .controlSize(.small)
                }
                if let command = CLIInstaller.shellCommand {
                    Button(cliCommandCopied ? "Copied!" : "Copy command") {
                        copyCLIShellCommand(command)
                    }
                    .controlSize(.small)
                }
                if case .notInstalled = cliSymlinkState {
                    Button("Try again") {
                        Task { await runInstall() }
                    }
                    .controlSize(.small)
                    .disabled(cliInstallBusy)
                }
                Spacer()
            }

            DisclosureGroup("Details", isExpanded: $cliErrorDetailsExpanded) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(cliErrorDetails(error))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(cliDetailsCopied ? "Copied!" : "Copy details") {
                        copyCLIErrorDetails(error)
                    }
                    .controlSize(.small)
                }
                .padding(.top, 4)
            }
            .font(.caption)
        }
        .padding(10)
        .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    private func runInstall() async {
        cliInstallBusy = true
        cliInstallError = nil
        cliErrorDetailsExpanded = false
        defer { cliInstallBusy = false }
        do {
            try await CLIInstaller.install()
            cliSymlinkState = CLIInstaller.symlinkState()
        } catch let error as CLIInstaller.CLIInstallerError {
            cliInstallError = error
        } catch {
            DiagnosticLog.log("[cli-install] unexpected error type: \(error)")
        }
    }

    private func runUninstall() async {
        cliInstallBusy = true
        cliInstallError = nil
        cliErrorDetailsExpanded = false
        defer { cliInstallBusy = false }
        do {
            try await CLIInstaller.uninstall()
            cliSymlinkState = CLIInstaller.symlinkState()
        } catch let error as CLIInstaller.CLIInstallerError {
            cliInstallError = error
        } catch {
            DiagnosticLog.log("[cli-install] unexpected error type: \(error)")
        }
    }

    private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(url)
        }
    }

    private func copyCLIShellCommand(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        cliCommandCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            cliCommandCopied = false
        }
    }

    private func cliErrorDetails(_ error: CLIInstaller.CLIInstallerError) -> String {
        var lines: [String] = []
        lines.append("error:         \(error.diagnosticPayload)")
        for (key, value) in CLIInstaller.diagnosticContext {
            lines.append("\(key.padding(toLength: 14, withPad: " ", startingAt: 0)) \(value)")
        }
        return lines.joined(separator: "\n")
    }

    private func copyCLIErrorDetails(_ error: CLIInstaller.CLIInstallerError) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cliErrorDetails(error), forType: .string)
        cliDetailsCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            cliDetailsCopied = false
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

                Button("Changelog") {
                    NSWorkspace.shared.open(URL(string: "https://clearly.md/changelog")!)
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

// MARK: - Sync Settings Tab

private struct SyncSettingsTab: View {
    @State private var iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
    @State private var usageByLocation: [UUID: VaultDiskUsage] = [:]
    @State private var computingLocationIDs: Set<UUID> = []

    private var workspace: WorkspaceManager { .shared }

    var body: some View {
        Form {
            Section("iCloud") {
                HStack {
                    Image(systemName: iCloudAvailable ? "checkmark.icloud.fill" : "xmark.icloud")
                        .foregroundStyle(iCloudAvailable ? .green : .secondary)
                    Text(iCloudAvailable ? "iCloud Drive is available" : "iCloud Drive is not available")
                    Spacer()
                }
                if !iCloudAvailable {
                    Text("Sign in to iCloud in System Settings to enable sync across devices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open iCloud Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            Section("Locations") {
                if workspace.locations.isEmpty {
                    Text("No locations added. Open a folder from the sidebar to see its sync details here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(workspace.locations) { location in
                        locationRow(location)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshAll() }
    }

    @ViewBuilder
    private func locationRow(_ location: BookmarkedLocation) -> some View {
        let usage = usageByLocation[location.id]
        let isComputing = computingLocationIDs.contains(location.id)
        let capability = syncCapability(for: location.url)
        let isCloud = capability != .local
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: capability.iconName)
                    .foregroundStyle(isCloud ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.name)
                        .font(.system(size: 13, weight: .medium))
                    Text(location.url.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let caption = capability.caption {
                        Text(caption)
                            .font(.caption2)
                            .foregroundStyle(capability == .local ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    }
                }
                Spacer()
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([location.url])
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
            HStack(spacing: 12) {
                if let usage {
                    Text("\(usage.totalCount) file\(usage.totalCount == 1 ? "" : "s") · \(formattedBytes(usage.totalBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if isCloud && usage.placeholderCount > 0 {
                        Text("\(usage.placeholderCount) not downloaded")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } else if isComputing {
                    Text("Calculating…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Refresh") { refresh(location) }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(isComputing)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Remove from List", role: .destructive) { remove(location) }
        }
    }

    private func remove(_ location: BookmarkedLocation) {
        guard workspace.removeLocationClosingOpenDocuments(location) else { return }
        usageByLocation.removeValue(forKey: location.id)
        computingLocationIDs.remove(location.id)
    }

    private func refreshAll() {
        iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
        for location in workspace.locations {
            refresh(location)
        }
    }

    private func refresh(_ location: BookmarkedLocation) {
        guard !computingLocationIDs.contains(location.id) else { return }
        computingLocationIDs.insert(location.id)
        let id = location.id
        let url = location.url
        Task {
            let usage = await VaultDiskUsage.compute(walking: url)
            await MainActor.run {
                usageByLocation[id] = usage
                computingLocationIDs.remove(id)
            }
        }
    }

    private enum SyncCapability {
        case iCloud
        case thirdPartyCloud
        case local

        var caption: String? {
            switch self {
            case .iCloud: return nil
            case .thirdPartyCloud: return "Synced by a third-party cloud provider."
            case .local: return "This folder won't sync across your devices."
            }
        }

        var iconName: String {
            switch self {
            case .iCloud: return "icloud"
            case .thirdPartyCloud: return "cloud"
            case .local: return "folder"
            }
        }
    }

    private func syncCapability(for url: URL) -> SyncCapability {
        let path = url.path
        if path.contains("/Mobile Documents/") { return .iCloud }
        // Third-party File Provider mounts (Google Drive, Dropbox, OneDrive, Box)
        // must be caught before the isUbiquitousItem fallback — that API returns
        // true for third-party providers too, not just iCloud.
        if path.contains("/Library/CloudStorage/") { return .thirdPartyCloud }
        // Catches iCloud Desktop & Documents sync, where the selected URL may
        // resolve to ~/Documents/... (firmlinked to Mobile Documents).
        if (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true {
            return .iCloud
        }
        return .local
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
