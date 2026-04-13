import SwiftUI

struct FindBarView: View {
    @ObservedObject var findState: FindState
    @FocusState private var isFieldFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12))

                TextField("Find", text: $findState.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isFieldFocused)
                    .onSubmit {
                        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                            findState.navigateToPrevious?()
                        } else {
                            findState.navigateToNext?()
                        }
                    }
                    .onExitCommand {
                        findState.isVisible = false
                    }

                if !findState.query.isEmpty {
                    if findState.matchCount > 0 {
                        Text("\(findState.currentIndex) of \(findState.matchCount)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else {
                        Text("No results")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor.opacity(isFieldFocused ? 0.4 : 0), lineWidth: 1)
                    .animation(Theme.Motion.hover, value: isFieldFocused)
            )

            HStack(spacing: 2) {
                FindNavButton(icon: "chevron.left", disabled: findState.matchCount == 0) {
                    findState.navigateToPrevious?()
                }
                FindNavButton(icon: "chevron.right", disabled: findState.matchCount == 0) {
                    findState.navigateToNext?()
                }
            }

            Button("Done") {
                findState.isVisible = false
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Theme.backgroundColorSwiftUI)
        .onAppear {
            isFieldFocused = true
        }
        .onChange(of: findState.focusRequest) { _, _ in
            isFieldFocused = true
        }
    }
}

private struct FindNavButton: View {
    let icon: String
    let disabled: Bool
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(disabled ? .quaternary : (isHovering ? .primary : .secondary))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovering && !disabled
                            ? Color.primary.opacity(colorScheme == .dark ? Theme.hoverOpacityDark : Theme.hoverOpacity)
                            : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering in
            withAnimation(Theme.Motion.hover) {
                isHovering = hovering
            }
        }
    }
}
