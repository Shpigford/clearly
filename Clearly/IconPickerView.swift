import SwiftUI
import Observation

@Observable
class IconPickerState {
    var selectedIcon: String?
    var selectedColor: String?

    init(icon: String?, color: String?) {
        self.selectedIcon = icon
        self.selectedColor = color
    }
}

struct IconPickerView: View {
    @Bindable var state: IconPickerState
    let onSelectIcon: (String?) -> Void
    let onSelectColor: (String?) -> Void

    private static let icons: [(String, String)] = [
        ("folder", "Default"),
        ("tray", "Inbox"),
        ("star", "Favorites"),
        ("archivebox", "Archive"),
        ("briefcase", "Work"),
        ("hammer", "Projects"),
        ("pencil.line", "Writing"),
        ("lightbulb", "Ideas"),
        ("magnifyingglass", "Research"),
        ("chevron.left.forwardslash.chevron.right", "Code"),
        ("paintbrush", "Design"),
        ("graduationcap", "Education"),
        ("dollarsign.circle", "Finance"),
        ("airplane", "Travel"),
        ("heart", "Health"),
        ("music.note", "Music"),
        ("photo", "Photos"),
        ("person", "Personal"),
        ("book", "Reading"),
        ("globe", "Web"),
        ("tag", "Tags"),
        ("bookmark", "Bookmarks"),
        ("clock", "Recent"),
        ("bubble.left", "Chat"),
        ("link", "Links"),
    ]

    private let iconColumns = Array(repeating: GridItem(.fixed(36), spacing: 6), count: 5)
    private let colorColumns = Array(repeating: GridItem(.fixed(22), spacing: 6), count: 9)

    var body: some View {
        VStack(spacing: 0) {
            // Color section
            Text("Color")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            LazyVGrid(columns: colorColumns, spacing: 6) {
                // No color option
                Button {
                    state.selectedColor = nil
                    onSelectColor(nil)
                } label: {
                    Circle()
                        .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                        .contentShape(Circle())
                        .overlay {
                            if state.selectedColor == nil {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help("No color")

                ForEach(Theme.folderColorPalette, id: \.name) { item in
                    Button {
                        state.selectedColor = item.name
                        onSelectColor(item.name)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(nsColor: item.color))
                                .frame(width: 18, height: 18)
                            if state.selectedColor == item.name {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(item.name.capitalized)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            // Icon section
            Text("Icon")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)

            LazyVGrid(columns: iconColumns, spacing: 6) {
                ForEach(Self.icons, id: \.0) { icon, label in
                    Button {
                        let newIcon = icon == "folder" ? nil : icon
                        state.selectedIcon = newIcon
                        onSelectIcon(newIcon)
                    } label: {
                        Image(systemName: icon)
                            .font(.system(size: 14))
                            .foregroundStyle(iconTint)
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(isIconSelected(icon) ? Color.primary.opacity(0.1) : Color.clear)
                            )
                            .help(label)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)

            if state.selectedIcon != nil || state.selectedColor != nil {
                Divider()
                Button("Reset All") {
                    state.selectedIcon = nil
                    state.selectedColor = nil
                    onSelectIcon(nil)
                    onSelectColor(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 260)
    }

    private var iconTint: Color {
        if let colorName = state.selectedColor,
           let nsColor = Theme.folderColor(named: colorName) {
            return Color(nsColor: nsColor)
        }
        return .secondary
    }

    private func isIconSelected(_ icon: String) -> Bool {
        if let selectedIcon = state.selectedIcon {
            return icon == selectedIcon
        }
        return icon == "folder"
    }
}
