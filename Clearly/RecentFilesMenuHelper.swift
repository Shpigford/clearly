import AppKit

class RecentMenuHelper: NSObject {
    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuDidBeginTracking(_:)),
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )
    }

    @objc private func menuDidBeginTracking(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        for item in menu.items {
            if let recentMenu = item.submenu,
               recentMenu.items.contains(where: { $0.action == #selector(NSDocumentController.clearRecentDocuments(_:)) }) {
                rewriteRecentMenuTitles(recentMenu)
                return
            }
        }
    }

    private func rewriteRecentMenuTitles(_ menu: NSMenu) {
        let recentURLs = NSDocumentController.shared.recentDocumentURLs
        var urlIndex = 0
        for item in menu.items {
            if item.isSeparatorItem || item.action == #selector(NSDocumentController.clearRecentDocuments(_:)) {
                continue
            }
            guard urlIndex < recentURLs.count else { break }
            let url = recentURLs[urlIndex]
            let filename = url.lastPathComponent
            let dir = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
            item.title = "\(filename) — \(dir)"
            urlIndex += 1
        }
    }
}
