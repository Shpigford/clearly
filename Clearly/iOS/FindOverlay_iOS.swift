#if os(iOS)
import SwiftUI
import ClearlyCore

struct FindOverlay_iOS: View {
    @ObservedObject var findState: FindState
    @FocusState private var focus: Field?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private enum Field: Hashable { case find, replace }

    private var hasRegexError: Bool { findState.regexError != nil }
    private var isCompact: Bool { horizontalSizeClass == .compact }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            findRow
            if findState.showReplace {
                replaceRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.backgroundColorSwiftUI)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.separatorColor(inDark: colorScheme == .dark))
                .frame(height: 1)
        }
        .animation(Theme.Motion.smooth, value: findState.showReplace)
        .onAppear { focus = .find }
        .onChange(of: findState.focusRequest) { _, _ in focus = .find }
        .onChange(of: findState.replaceFocusRequest) { _, _ in focus = .replace }
    }

    private var findRow: some View {
        HStack(spacing: 8) {
            chevronButton

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
                    .focused($focus, equals: .find)
                    .onSubmit { findState.navigateToNext?() }

                FindOptionToggle_iOS(label: "Aa", help: "Match case", isOn: $findState.caseSensitive)
                FindOptionToggle_iOS(label: ".*", help: "Regular expression", isOn: $findState.useRegex)

                statusText

                if !findState.query.isEmpty {
                    Button {
                        findState.query = ""
                        focus = .find
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
                    .strokeBorder(borderColor, lineWidth: 1)
                    .animation(Theme.Motion.hover, value: focus)
                    .animation(Theme.Motion.hover, value: hasRegexError)
            )

            // Compact-width: drop prev/next from row 1 when replace is open;
            // the replace row already gives Replace+advance and Replace All.
            if !(isCompact && findState.showReplace) {
                HStack(spacing: 2) {
                    FindNavButton_iOS(icon: "chevron.up", disabled: !findState.canNavigate) {
                        findState.navigateToPrevious?()
                    }
                    FindNavButton_iOS(icon: "chevron.down", disabled: !findState.canNavigate) {
                        findState.navigateToNext?()
                    }
                }
            }

            Button("Done") {
                findState.dismiss()
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.accentColorSwiftUI)
        }
    }

    private var replaceRow: some View {
        HStack(spacing: 8) {
            chevronSpacer

            HStack(spacing: 6) {
                Image(systemName: "arrow.uturn.forward")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 13))

                TextField("Replace", text: $findState.replacementText)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.findField)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .focused($focus, equals: .replace)
                    .onSubmit { findState.editorPerformReplace?() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.accentColorSwiftUI.opacity(focus == .replace ? 0.4 : 0), lineWidth: 1)
                    .animation(Theme.Motion.hover, value: focus)
            )

            Button("All") { findState.editorPerformReplaceAll?() }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(findState.canReplaceAll ? Theme.accentColorSwiftUI : Color.secondary)
                .disabled(!findState.canReplaceAll)

            Button("Replace") { findState.editorPerformReplace?() }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(findState.canReplace ? Theme.accentColorSwiftUI : Color.secondary)
                .disabled(!findState.canReplace)
        }
    }

    private var chevronButton: some View {
        Button {
            findState.showReplace.toggle()
            findState.lastReplaceCount = nil
        } label: {
            Image(systemName: findState.showReplace ? "chevron.down" : "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(findState.showReplace ? "Hide replace" : "Show replace")
    }

    private var chevronSpacer: some View {
        Color.clear.frame(width: 24, height: 32)
    }

    @ViewBuilder
    private var statusText: some View {
        if let count = findState.lastReplaceCount {
            Text(count == 1 ? "Replaced 1" : "Replaced \(count)")
                .font(Theme.Typography.findCount)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        } else if let error = findState.regexError {
            Text(error)
                .font(Theme.Typography.findCount)
                .foregroundStyle(.red.opacity(0.8))
                .lineLimit(1)
        } else if !findState.query.isEmpty && !findState.resultsAreStale {
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
    }

    private var borderColor: Color {
        if hasRegexError { return Color.red.opacity(0.5) }
        if focus == .find { return Theme.accentColorSwiftUI.opacity(0.4) }
        return Color.clear
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

private struct FindOptionToggle_iOS: View {
    let label: String
    let help: String
    @Binding var isOn: Bool

    var body: some View {
        Button(action: { isOn.toggle() }) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(isOn ? Theme.accentColorSwiftUI : Color.secondary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isOn ? Theme.accentColorSwiftUI.opacity(0.18) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(help)
    }
}
#endif
