import AuthenticationServices
import SwiftUI

struct AccountsSettingsView: View {
    @Environment(AccountManager.self) private var account
    @State private var mode: Mode = .signIn
    @State private var email: String = ""
    @State private var password: String = ""

    private enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign In"
        case signUp = "Create Account"
        var id: String { rawValue }
    }

    var body: some View {
        Form {
            if let user = account.currentUser {
                signedInSection(user: user)
            } else {
                signedOutSection
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func signedInSection(user: SyncAPIUser) -> some View {
        Section("Account") {
            LabeledContent("Signed in as") {
                Text(user.emailAddress ?? "(private relay)")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Plan") {
                Text(user.subscriptionStatus.capitalized)
                    .foregroundStyle(.secondary)
            }
            Button("Sign Out", role: .destructive) {
                Task { await account.signOut() }
            }
        }
    }

    @ViewBuilder
    private var signedOutSection: some View {
        Section {
            SignInWithAppleButton(
                onRequest: { request in
                    account.prepareAppleRequest(on: request)
                },
                onCompletion: { result in
                    switch result {
                    case .success(let auth):
                        if let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                            Task { await account.signInWithApple(credential: credential) }
                        }
                    case .failure(let error):
                        // Silently ignore user-cancel, surface everything else.
                        let nsError = error as NSError
                        if nsError.code != ASAuthorizationError.canceled.rawValue {
                            account.lastError = error.localizedDescription
                        }
                    }
                }
            )
            .signInWithAppleButtonStyle(.black)
            .frame(height: 32)
        }

        Section {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField("Email", text: $email)
                .textContentType(.emailAddress)
            SecureField("Password", text: $password)
                .textContentType(mode == .signIn ? .password : .newPassword)

            Button(mode.rawValue) {
                Task {
                    switch mode {
                    case .signIn:
                        await account.signInEmail(email: email, password: password)
                    case .signUp:
                        await account.signUpEmail(email: email, password: password)
                    }
                }
            }
            .disabled(email.isEmpty || password.isEmpty || account.isAuthenticating)
        }

        if let error = account.lastError {
            Section {
                Text(error).foregroundStyle(.red)
            }
        }
    }
}
