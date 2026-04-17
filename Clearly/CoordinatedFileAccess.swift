import Foundation

enum CoordinatedFileAccess {
    static func readData(from url: URL) throws -> Data {
        try coordinatedRead(from: url) { coordinatedURL in
            try Data(contentsOf: coordinatedURL)
        }
    }

    static func readText(from url: URL, encoding: String.Encoding = .utf8) throws -> String {
        let data = try readData(from: url)
        guard let text = String(data: data, encoding: encoding) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text
    }

    static func writeData(_ data: Data, to url: URL, options: Data.WritingOptions = [.atomic]) throws {
        try coordinatedWrite(to: url) { coordinatedURL in
            try data.write(to: coordinatedURL, options: options)
        }
    }

    static func writeText(_ text: String, to url: URL, atomically: Bool = true, encoding: String.Encoding = .utf8) throws {
        try coordinatedWrite(to: url) { coordinatedURL in
            try text.write(to: coordinatedURL, atomically: atomically, encoding: encoding)
        }
    }

    static func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    @discardableResult
    static func itemExists(at url: URL, isDirectory: inout ObjCBool) -> Bool {
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
    }

    static func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
    }

    static func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }

    static func trashItem(at url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    static func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]? = nil,
        options: FileManager.DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: options)
    }

    static func attributesOfItem(at url: URL) throws -> [FileAttributeKey: Any] {
        try FileManager.default.attributesOfItem(atPath: url.path)
    }

    private static func coordinatedRead<T>(from url: URL, accessor: (URL) throws -> T) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = Result { try accessor(coordinatedURL) }
        }

        if let coordinationError {
            throw coordinationError
        }

        guard let result else {
            throw CocoaError(.fileReadUnknown)
        }

        return try result.get()
    }

    private static func coordinatedWrite<T>(to url: URL, accessor: (URL) throws -> T) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = Result { try accessor(coordinatedURL) }
        }

        if let coordinationError {
            throw coordinationError
        }

        guard let result else {
            throw CocoaError(.fileWriteUnknown)
        }

        return try result.get()
    }
}
