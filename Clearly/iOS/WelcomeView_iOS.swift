import SwiftUI
import ClearlyCore

struct WelcomeView_iOS: View {
    @Environment(VaultSession.self) private var session
    @Environment(\.horizontalSizeClass) private var sizeClass

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

    private var isIPad: Bool { sizeClass == .regular }
    private var contentWidth: CGFloat { isIPad ? 440 : .infinity }

    var body: some View {
        ZStack {
            Theme.backgroundColorSwiftUI.ignoresSafeArea()

            if session.error == .bookmarkInvalidated {
                bookmarkInvalidated
            } else {
                VStack(spacing: 0) {
                    Spacer()

                    hero
                        .padding(.bottom, 44)

                    actions

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Theme.errorColorSwiftUI)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.top, 20)
                    }

                    Spacer()
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
            }
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

    // MARK: - Bookmark invalidated

    /// Shown when the persisted security-scoped bookmark failed to resolve on
    /// launch (`VaultSession.error == .bookmarkInvalidated`). The previous
    /// bookmark is already cleared from `UserDefaults`; the user has to
    /// re-pick explicitly — no auto-fallback to the default iCloud container,
    /// since silently switching vaults would lose them in a different folder.
    private var bookmarkInvalidated: some View {
        ContentUnavailableView {
            Label("Your vault folder couldn't be found", systemImage: "folder.badge.questionmark")
        } description: {
            Text("Clearly lost access to the folder you picked. It may have been renamed, moved, or removed. Choose your vault again to continue.")
        } actions: {
            Button {
                pickerMode = .pickedICloud
            } label: {
                Text("Choose Vault")
                    .frame(maxWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Theme.accentColorSwiftUI)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 20) {
            appIcon
            VStack(spacing: 8) {
                Text("Welcome to Clearly")
                    .font(.largeTitle.weight(.bold))
                    .tracking(-0.4)
                    .multilineTextAlignment(.center)
                Text("Your markdown notes, on every device.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    /// 90pt brand mark — uses the real `AppIcon.icon` baked into the bundle
    /// so the welcome screen matches the Home Screen icon exactly. Falls
    /// back to a styled gradient placeholder if the icon lookup ever fails
    /// (defensive — should never hit in shipped builds).
    private var appIcon: some View {
        let corner: CGFloat = 20 // ≈ 22% of 90 — matches iOS Home Screen masking
        return Group {
            if let uiImage = Self.bundleAppIcon() {
                Image(uiImage: uiImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 90, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Theme.accentColorSwiftUI,
                                    Theme.accentColorSwiftUI.opacity(0.82)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 90, height: 90)

                    Image(systemName: "doc.text")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 10)
        .shadow(color: Color.black.opacity(0.08), radius: 3, y: 1)
    }

    /// Pull the primary app icon out of `CFBundleIcons`. iOS doesn't expose
    /// `Image("AppIcon")` directly (the asset name is special), so we walk
    /// the Info.plist structure that the asset compiler emits and load the
    /// largest variant by name. Same trick Apple's own apps use for "About"
    /// screens.
    private static func bundleAppIcon() -> UIImage? {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let lastFile = files.last else {
            return nil
        }
        return UIImage(named: lastFile)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                attachDefaultICloud()
            } label: {
                Text("Use iCloud")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Theme.accentColorSwiftUI)
            .disabled(!isICloudAvailable)

            Button {
                pickerMode = .pickedICloud
            } label: {
                Text("Choose a Folder…")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            if !isICloudAvailable {
                Text("Sign in to iCloud in Settings to enable sync across your devices.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                    .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: contentWidth)
    }

    // MARK: - Actions

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
                // Heuristic: if the picked URL lives under `Mobile Documents`
                // (iCloud Drive), remember it as a picked-iCloud vault. The
                // previous two-button flow made the user pre-declare this;
                // auto-detecting keeps one "Choose Folder" path that handles
                // both cases, which matches iOS's combined picker UX.
                let kind: VaultLocation.Kind = isICloudURL(url) ? .pickedICloud : .local
                session.attach(VaultLocation(kind: kind, url: url, bookmarkData: bookmark))
            } catch {
                url.stopAccessingSecurityScopedResource()
                errorMessage = "Couldn't remember that folder: \(error.localizedDescription)"
            }
        }
    }

    private func isICloudURL(_ url: URL) -> Bool {
        url.standardizedFileURL.path.contains("/Mobile Documents/")
    }
}
