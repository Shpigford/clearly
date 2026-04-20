import Foundation
import ClearlyCore

final class FileWatcher: ObservableObject {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var debounceWork: DispatchWorkItem?
    private var monitoredURL: URL?
    private var currentText: String?
    private var lastKnownDiskText: String?
    var onChange: ((String) -> Void)?
    var liveCurrentText: (() -> String?)?

    func watch(_ url: URL?, currentText: String? = nil) {
        stopMonitoring()
        monitoredURL = url
        self.currentText = currentText
        lastKnownDiskText = currentText
        guard let url else { return }
        startMonitoring(url)
    }

    func updateCurrentText(_ text: String) {
        currentText = text
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Private

    private func startMonitoring(_ url: URL) {
        let fd = open(url.path, O_EVTONLY)
        guard fd != -1 else { return }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .link, .extend, .attrib],
            queue: .global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                // Atomic save: file was replaced. Tear down and re-establish.
                self.stopMonitoring()
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self, let url = self.monitoredURL else { return }
                    self.startMonitoring(url)
                    self.readAndNotify()
                }
                return
            }
            self.debouncedReadAndNotify()
        }

        source.setCancelHandler { [fd] in
            close(fd)
        }

        source.resume()
        self.source = source
    }

    private func stopMonitoring() {
        debounceWork?.cancel()
        debounceWork = nil
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }

    private func debouncedReadAndNotify() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.readAndNotify()
        }
        debounceWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func readAndNotify() {
        guard let url = monitoredURL else { return }
        guard let data = try? Data(contentsOf: url),
              let newText = String(data: data, encoding: .utf8) else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard newText != self.lastKnownDiskText else { return }

            if let liveCurrentText = self.liveCurrentText?() {
                self.currentText = liveCurrentText
            }
            let hasUnsavedChanges = self.currentText != self.lastKnownDiskText
            self.lastKnownDiskText = newText

            guard !hasUnsavedChanges else {
                DiagnosticLog.log("External file change ignored: unsaved local edits")
                return
            }

            self.currentText = newText
            self.onChange?(newText)
        }
    }
}
