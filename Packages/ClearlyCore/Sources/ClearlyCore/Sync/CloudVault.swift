import Foundation
import Combine

public enum CloudVault {
    public static let containerIdentifier = "iCloud.com.sabotage.clearly"

    public static func ubiquityContainerURL() async -> URL? {
        await Task.detached(priority: .utility) {
            guard let container = FileManager.default
                .url(forUbiquityContainerIdentifier: containerIdentifier)
            else { return nil }
            let documents = container.appendingPathComponent("Documents", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: documents, withIntermediateDirectories: true
            )
            return documents
        }.value
    }

    public static var isAvailablePublisher: AnyPublisher<Bool, Never> {
        NotificationCenter.default
            .publisher(for: .NSUbiquityIdentityDidChange)
            .map { _ in FileManager.default.ubiquityIdentityToken != nil }
            .prepend(FileManager.default.ubiquityIdentityToken != nil)
            .eraseToAnyPublisher()
    }
}
