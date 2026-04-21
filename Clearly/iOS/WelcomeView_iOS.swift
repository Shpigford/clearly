import SwiftUI
import ClearlyCore

struct WelcomeView_iOS: View {
    @Environment(VaultSession.self) private var session

    @State private var isICloudAvailable: Bool = FileManager.default.ubiquityIdentityToken != nil
    @State private var pickerMode: PickerMode?
    @State private var errorMessage: String?

    enum PickerMode: Identifiable {
        case pickedICloud
        case local
        var id: Int {
            switch self {
            case .pickedICloud: return 1
            case .local: return 2
            }
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Clearly")
                    .font(.largeTitle.weight(.semibold))
                Text("Pick a folder of `.md` files to get started.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 12) {
                Button {
                    attachDefaultICloud()
                } label: {
                    optionLabel(
                        title: "Use iCloud Drive → Clearly",
                        subtitle: isICloudAvailable ? "Sync with your Mac automatically" : "Sign in to iCloud to enable",
                        systemImage: "icloud"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!isICloudAvailable)

                Button {
                    pickerMode = .pickedICloud
                } label: {
                    optionLabel(
                        title: "Choose iCloud folder…",
                        subtitle: "Pick an existing folder in iCloud Drive",
                        systemImage: "folder.badge.plus"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    pickerMode = .local
                } label: {
                    optionLabel(
                        title: "Choose local folder…",
                        subtitle: "On this device only — no sync",
                        systemImage: "iphone"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
        .fileImporter(
            isPresented: Binding(
                get: { pickerMode != nil },
                set: { if !$0 { pickerMode = nil } }
            ),
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result: result, mode: pickerMode ?? .local)
        }
        .task {
            for await available in CloudVault.isAvailablePublisher.values {
                isICloudAvailable = available
            }
        }
    }

    @ViewBuilder
    private func optionLabel(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func attachDefaultICloud() {
        errorMessage = nil
        Task {
            guard let url = await CloudVault.ubiquityContainerURL() else {
                errorMessage = "iCloud Drive isn't available. Sign in from Settings and try again."
                return
            }
            session.attach(VaultLocation(kind: .defaultICloud, url: url))
        }
    }

    private func handleImport(result: Result<[URL], Error>, mode: PickerMode) {
        errorMessage = nil
        switch result {
        case .failure(let error):
            errorMessage = "Couldn't open folder: \(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Couldn't access that folder — permission denied."
                return
            }
            do {
                let bookmark = try url.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                let kind: VaultLocation.Kind = (mode == .pickedICloud) ? .pickedICloud : .local
                session.attach(VaultLocation(kind: kind, url: url, bookmarkData: bookmark))
            } catch {
                url.stopAccessingSecurityScopedResource()
                errorMessage = "Couldn't remember that folder: \(error.localizedDescription)"
            }
        }
    }
}
