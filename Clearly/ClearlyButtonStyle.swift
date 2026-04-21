import SwiftUI
import ClearlyCore

struct ClearlyToolbarButtonStyle: ButtonStyle {
    var isActive: Bool = false
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let hoverOpacity = colorScheme == .dark ? Theme.hoverOpacityDark : Theme.hoverOpacity

        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(isActive ? Color.accentColor : (isHovering ? .primary : .secondary))
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive
                        ? Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.12)
                        : (isHovering || configuration.isPressed
                            ? Color.primary.opacity(configuration.isPressed ? hoverOpacity + 0.04 : hoverOpacity)
                            : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { hovering in
                withAnimation(Theme.Motion.hover) {
                    isHovering = hovering
                }
            }
    }
}
