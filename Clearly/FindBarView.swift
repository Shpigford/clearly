import SwiftUI

struct FindBarView: View {
    @ObservedObject var findState: FindState
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
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
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else {
                        Text("No results")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
            )

            HStack(spacing: 2) {
                Button {
                    findState.navigateToPrevious?()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(findState.matchCount == 0)

                Button {
                    findState.navigateToNext?()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(findState.matchCount == 0)
            }

            Button("Done") {
                findState.isVisible = false
            }
            .buttonStyle(.borderless)
            .font(.system(size: 13))
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
