import SwiftUI
import ClearlyCore

struct JumpToLineBar: View {
    @ObservedObject var state: JumpToLineState
    @FocusState private var isFieldFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "number")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12))

                TextField("Line number", text: $state.lineText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13).monospacedDigit())
                    .focused($isFieldFocused)
                    .onSubmit {
                        state.commit()
                    }
                    .onExitCommand {
                        state.dismiss()
                    }
                    .onChange(of: state.lineText) { _, newValue in
                        let filtered = newValue.filter(\.isNumber)
                        if filtered != newValue {
                            state.lineText = filtered
                        }
                    }

                if state.totalLines > 0 {
                    Text("of \(state.totalLines)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
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

            Button("Go") {
                state.commit()
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
        .onChange(of: state.focusRequest) { _, _ in
            isFieldFocused = true
        }
    }
}
