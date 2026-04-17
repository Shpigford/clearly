import Foundation

enum ICloudVaultError: LocalizedError {
    case accountUnavailable
    case containerUnavailable

    var errorDescription: String? {
        switch self {
        case .accountUnavailable:
            return "Sign in to iCloud to use the Clearly iCloud vault."
        case .containerUnavailable:
            return "Clearly couldn't open its iCloud container yet."
        }
    }
}

enum ICloudDownloadState {
    case ready
    case downloading
}

enum ICloudVaultSupport {
    static let containerIdentifier = "iCloud.com.sabotage.clearly"
    static let vaultFolderName = "Clearly"

    static var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    static func resolveVaultURL() throws -> URL {
        guard isAvailable else {
            throw ICloudVaultError.accountUnavailable
        }

        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) else {
            throw ICloudVaultError.containerUnavailable
        }

        let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
        let vaultURL = documentsURL.appendingPathComponent(vaultFolderName, isDirectory: true)
        try CoordinatedFileAccess.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        return vaultURL.standardizedFileURL
    }

    static func prepareForReading(_ url: URL) throws -> ICloudDownloadState {
        let values = try url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
        ])

        guard values.isUbiquitousItem == true else {
            return .ready
        }

        if values.ubiquitousItemDownloadingStatus == URLUbiquitousItemDownloadingStatus.current {
            return .ready
        }

        try FileManager.default.startDownloadingUbiquitousItem(at: url)
        return .downloading
    }
}
