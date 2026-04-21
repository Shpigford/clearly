import SwiftUI
import AppKit
import ClearlyCore

struct WelcomeView: View {
    var workspace: WorkspaceManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .padding(.bottom, 16)

                Text("Welcome to Clearly")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.primary)
                    .tracking(-0.3)
                    .padding(.bottom, 6)

                Text("A quiet place for your markdown and your thinking.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 36)

                HStack(spacing: 16) {
                    WelcomePathCard(
                        icon: "folder.badge.plus",
                        title: "Add a Folder",
                        description: "Point Clearly at a folder of markdown files to unlock the sidebar, backlinks, tags, and search.",
                        isPrimary: true,
                        colorScheme: colorScheme
                    ) {
                        showFolderPicker()
                    }

                    WelcomePathCard(
                        icon: "doc.text",
                        title: "Quick Edit",
                        description: "Start writing right away with a blank document, or open an existing file.",
                        isPrimary: false,
                        colorScheme: colorScheme
                    ) {
                        workspace.createUntitledDocument()
                    }
                }
                .frame(maxWidth: 520)

                Button("or open an existing file\u{2026}") {
                    workspace.showOpenPanel()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 14)
            }
            .position(x: geo.size.width / 2, y: geo.size.height * 0.42)
        }
        .background(Theme.backgroundColorSwiftUI)
    }

    private func showFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Choose a folder of markdown files"
        panel.prompt = "Add Folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard !workspace.locations.contains(where: { $0.url == url }) else { return }

        let shouldShowGettingStarted = workspace.isFirstRun
        guard workspace.addLocation(url: url) else { return }
        if shouldShowGettingStarted {
            workspace.handleFirstLocationIfNeeded(folderURL: url)
        }

        // Show sidebar by finding the split view controller through the window hierarchy
        if let splitVC = NSApp.mainWindow?.contentViewController as? ClearlySplitViewController {
            splitVC.setSidebarVisible(true, animated: false)
        }
        workspace.isSidebarVisible = true
        UserDefaults.standard.set(true, forKey: "sidebarVisible")
    }
}

// MARK: - Path Card

private struct WelcomePathCard: View {
    let icon: String
    let title: String
    let description: String
    let isPrimary: Bool
    let colorScheme: ColorScheme
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(isPrimary ? Theme.accentColorSwiftUI : .secondary)
                    .padding(.bottom, 10)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.bottom, 4)

                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Theme.Motion.hover) {
                isHovered = hovering
            }
        }
    }

    private var cardFill: Color {
        if isPrimary {
            let base = colorScheme == .dark ? 0.08 : 0.05
            let hover = isHovered ? 0.04 : 0.0
            return Theme.accentColorSwiftUI.opacity(base + hover)
        } else {
            let base = colorScheme == .dark ? 0.04 : 0.02
            let hover = isHovered ? 0.03 : 0.0
            return Color.primary.opacity(base + hover)
        }
    }

    private var cardStroke: Color {
        if isPrimary {
            return Theme.accentColorSwiftUI.opacity(colorScheme == .dark ? 0.25 : 0.15)
        } else {
            return Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06)
        }
    }
}
