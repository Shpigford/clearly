import SwiftUI

/// Transient HUD that appears while a Wiki recipe is running. Mounted on top
/// of `MacDetailColumn`'s content via `.overlay` — dismisses automatically
/// when the controller reports the recipe finished (either by staging an op,
/// which triggers the diff sheet, or by failing, which surfaces an alert).
struct WikiRecipeProgressOverlay: View {
    @Bindable var controller: WikiOperationController

    var body: some View {
        if controller.isRunningRecipe {
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(controller.recipeStatus ?? "Working…")
                            .font(.callout)
                            .foregroundStyle(.primary)
                        Text("First call after launch warms the cache (~30s). Subsequent calls are fast.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThickMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
                .frame(maxWidth: 460)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}
