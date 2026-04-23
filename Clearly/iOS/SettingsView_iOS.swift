#if os(iOS)
import SwiftUI
import UIKit
import ClearlyCore
import Combine

struct SettingsView_iOS: View {
    @Environment(VaultSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
    @State private var usage: VaultDiskUsage?
    @State private var computing = false

    private let iCloudPublisher = CloudVault.isAvailablePublisher

    var body: some View {
        NavigationStack {
            Form {
                Section("Vault") {
                    if let vault = session.currentVault {
                        LabeledContent("Location", value: vault.displayName)
                        LabeledContent("Kind") {
                            Text(kindLabel(vault.kind))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No vault attached.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("iCloud") {
                    HStack {
                        Image(systemName: iCloudAvailable ? "checkmark.icloud.fill" : "xmark.icloud")
                            .foregroundStyle(iCloudAvailable ? .green : .secondary)
                        Text(iCloudAvailable ? "Signed in" : "Not signed in")
                    }
                    if !iCloudAvailable {
                        Text("Sign in to iCloud in Settings to sync notes across devices.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Storage") {
                    if let usage {
                        LabeledContent("Files", value: "\(usage.totalCount)")
                        LabeledContent("Total size", value: formattedBytes(usage.totalBytes))
                        if usage.placeholderCount > 0 {
                            LabeledContent("Not downloaded", value: "\(usage.placeholderCount) file\(usage.placeholderCount == 1 ? "" : "s")")
                        }
                    } else if computing {
                        HStack {
                            ProgressView()
                            Text("Calculating…")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("—")
                            .foregroundStyle(.secondary)
                    }
                    Button("Refresh", action: recompute)
                        .disabled(computing || session.currentVault == nil)
                }

                Section("Help") {
                    Button {
                        openReportURL()
                    } label: {
                        Label("Report a Bug…", systemImage: "ladybug")
                    }
                    Button {
                        openURL(URL(string: "https://clearly.md/changelog")!)
                    } label: {
                        Label("What’s New", systemImage: "sparkles")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
                if usage == nil { recompute() }
            }
            .onReceive(iCloudPublisher) { available in
                iCloudAvailable = available
            }
        }
    }

    private func recompute() {
        guard let url = session.currentVault?.url else { return }
        computing = true
        Task {
            let result = await VaultDiskUsage.compute(walking: url)
            await MainActor.run {
                usage = result
                computing = false
            }
        }
    }

    private func kindLabel(_ kind: VaultLocation.Kind) -> String {
        switch kind {
        case .defaultICloud: return "iCloud Drive"
        case .pickedICloud: return "iCloud (custom folder)"
        case .local: return "Local"
        }
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func openReportURL() {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?"
        let platform: BugReportURL.Platform = UIDevice.current.userInterfaceIdiom == .pad ? .iPadOS : .iOS
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let hw = String(cString: machine)
        let url = BugReportURL.build(
            platform: platform,
            appVersion: "\(version) (\(build))",
            osVersion: "\(platform.rawValue) \(UIDevice.current.systemVersion)",
            device: hw.isEmpty ? nil : hw
        )
        openURL(url)
    }
}
#endif
