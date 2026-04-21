import SwiftUI
import ClearlyCore

struct ClearlySegmentedControl<T: Hashable & CaseIterable & RawRepresentable>: View where T.RawValue == String, T.AllCases: RandomAccessCollection {
    @Binding var selection: T
    let items: [(value: T, icon: String, label: String)]
    @Namespace private var animation
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.value.rawValue) { item in
                Button {
                    withAnimation(Theme.Motion.smooth) {
                        selection = item.value
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: item.icon)
                            .font(.system(size: 12, weight: .medium))
                        Text(item.label)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(selection == item.value ? .primary : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background {
                        if selection == item.value {
                            Capsule()
                                .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
                                .matchedGeometryEffect(id: "activeSegment", in: animation)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            Capsule()
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04))
        )
    }
}
