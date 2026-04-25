import SwiftUI
import ClearlyCore

/// Proper SwiftUI sheet for `Wiki → Capture`. Multi-line input — the user
/// can paste a URL OR an arbitrary block of text. Submit fires the
/// classify-then-run pipeline; Cancel just dismisses.
///
/// ⌘⏎ to capture, Esc to cancel. Input field auto-focuses on appear.
struct WikiCaptureSheet: View {
    @Bindable var state: WikiCaptureState
    let onSubmit: (String) -> Void

    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            input
            Divider()
            footer
        }
        .frame(minWidth: 520, idealWidth: 580, minHeight: 320, idealHeight: 360)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Capture")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Paste a URL or any text you want the agent to summarize and file.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    // MARK: - Input

    private var input: some View {
        ZStack(alignment: .topLeading) {
            // Subtle textured background; matches the rest of Clearly.
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                )

            TextEditor(text: $state.draft)
                .scrollContentBackground(.hidden)
                .font(.body)
                .padding(.horizontal, 3)
                .padding(.vertical, 8)
                .focused($inputFocused)

            if state.draft.isEmpty {
                // Same x = TextEditor.padding(3) + NSTextView lineFragmentPadding (~5) = 8.
                // Same y = TextEditor.padding(8) + NSTextView baseline offset (~0) = 8.
                // Anything else makes the placeholder and the cursor disagree.
                Text("https://… or paste text here")
                    .font(.body)
                    .foregroundStyle(.secondary.opacity(0.55))
                    .padding(.leading, 8)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // SwiftUI delays focus until the sheet's window is fully on screen.
            DispatchQueue.main.async { inputFocused = true }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer()
            Button("Cancel") { state.dismiss() }
                .keyboardShortcut(.cancelAction)

            Button("Capture") { submit() }
                .keyboardShortcut(.defaultAction)
                .disabled(state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func submit() {
        let text = state.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let payload = state.draft
        state.dismiss()
        onSubmit(payload)
    }
}
