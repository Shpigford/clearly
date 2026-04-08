import SwiftUI

struct IconPickerView: View {
    let currentIcon: String?
    let onSelect: (String?) -> Void

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

    private let columns = Array(repeating: GridItem(.fixed(36), spacing: 6), count: 5)

    var body: some View {
        VStack(spacing: 0) {
            Text("Folder Icon")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 10)
                .padding(.bottom, 6)

            Divider()

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Self.icons, id: \.0) { icon, label in
                    Button {
                        // "folder" means reset to default
                        onSelect(icon == "folder" ? nil : icon)
                    } label: {
                        Image(systemName: icon)
                            .font(.system(size: 14))
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(isSelected(icon) ? Color.accentColor.opacity(0.2) : Color.clear)
                            )
                            .help(label)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)

            if currentIcon != nil {
                Divider()
                Button("Reset to Default") {
                    onSelect(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 232)
    }

    private func isSelected(_ icon: String) -> Bool {
        if let currentIcon {
            return icon == currentIcon
        }
        return icon == "folder"
    }
}
