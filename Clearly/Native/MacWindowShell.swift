import SwiftUI
import ClearlyCore

/// Feature-flag helpers for the native-shell rebuild.
///
/// When `UseNativeMacShell` is true the SwiftUI `Window` scene in `ClearlyApp`
/// presents `MacRootView` and the legacy `ClearlyAppDelegate.createMainWindow()`
/// AppKit path short-circuits. When false the old AppKit shell renders.
///
/// Toggle: `defaults write com.sabotage.clearly.dev UseNativeMacShell -bool YES`.
/// Replace `.dev` with `.clearly` for release builds. Restart the app after
/// changing the flag.
@MainActor
enum NativeMacShell {
    static let userDefaultsKey = "UseNativeMacShell"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsKey)
    }
}

/// Content view for the native `Window` scene. Renders `MacRootView` when the
/// flag is on, otherwise a zero-sized hidden view so the scene stays inert.
struct NativeMainWindowContent: View {
    @AppStorage(NativeMacShell.userDefaultsKey) private var useNative = false
    @Bindable var workspace: WorkspaceManager = .shared

    var body: some View {
        if useNative {
            MacRootView(workspace: workspace)
        } else {
            // Suppressed path — keeps the scene declaration valid without
            // rendering anything. `.defaultLaunchBehavior(.suppressed)` on
            // the scene prevents this window from auto-opening anyway.
            Color.clear.frame(width: 0, height: 0)
        }
    }
}
