import ArgumentParser
import Foundation

struct TagsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tags",
        abstract: "List tags or files for a tag (arrives in Phase 4)."
    )

    func run() async throws {
        FileHandle.standardError.write(
            Data("clearly tags — not yet implemented (Phase 4)\n".utf8)
        )
        throw ExitCode(Exit.usage)
    }
}
