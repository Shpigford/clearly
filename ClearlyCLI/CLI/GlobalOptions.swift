import ArgumentParser
import ClearlyCore

enum OutputFormat: String, ExpressibleByArgument, Codable, Sendable {
    case json
    case text
}

struct GlobalOptions: ParsableArguments {
    @Option(
        name: .long,
        parsing: .singleValue,
        help: "Vault name or path to load. Repeat to load multiple; omit to load all configured."
    )
    var vault: [String] = []

    @Option(
        name: .long,
        help: "Output format: json (default) or text."
    )
    var format: OutputFormat = .json

    @Option(
        name: .customLong("bundle-id"),
        help: "Override the Clearly app bundle identifier for vault discovery."
    )
    var bundleID: String = "com.sabotage.clearly"

    init() {}
}
