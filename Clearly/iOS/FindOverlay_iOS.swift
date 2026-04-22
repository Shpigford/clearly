#if os(iOS)
import SwiftUI
import ClearlyCore

struct FindOverlay_iOS: View {
    @ObservedObject var findState: FindState
    @FocusState private var isFieldFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 13))

                TextField("Find", text: $findState.query)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.findField)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .focused($isFieldFocused)
                    .onSubmit { findState.navigateToNext?() }

                if !findState.query.isEmpty {
                    if findState.matchCount > 0 {
                        Text("\(findState.currentIndex) of \(findState.matchCount)")
                            .font(Theme.Typography.findCount)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else {
                        Text("No results")
                            .font(Theme.Typography.findCount)
                            .foregroundStyle(.secondary)
                    }
                }

                if !findState.query.isEmpty {
                    Button {
                        findState.query = ""
                        isFieldFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.accentColorSwiftUI.opacity(isFieldFocused ? 0.4 : 0), lineWidth: 1)
                    .animation(Theme.Motion.hover, value: isFieldFocused)
            )

            HStack(spacing: 2) {
                FindNavButton_iOS(icon: "chevron.up", disabled: findState.matchCount == 0) {
                    findState.navigateToPrevious?()
                }
                FindNavButton_iOS(icon: "chevron.down", disabled: findState.matchCount == 0) {
                    findState.navigateToNext?()
                }
            }

            Button("Done") {
                findState.dismiss()
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.accentColorSwiftUI)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.backgroundColorSwiftUI)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.separatorColor(inDark: colorScheme == .dark))
                .frame(height: 1)
        }
        .onAppear { isFieldFocused = true }
        .onChange(of: findState.focusRequest) { _, _ in
            isFieldFocused = true
        }
    }
}

private struct FindNavButton_iOS: View {
    let icon: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(disabled ? .quaternary : .secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
#endif
