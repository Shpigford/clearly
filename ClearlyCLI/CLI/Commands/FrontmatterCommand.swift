import ArgumentParser
import Foundation

struct FrontmatterCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "frontmatter",
        abstract: "Read YAML frontmatter from a note (arrives in Phase 2)."
    )

    func run() async throws {
        FileHandle.standardError.write(
            Data("clearly frontmatter — not yet implemented (Phase 2)\n".utf8)
        )
        throw ExitCode(Exit.usage)
    }
}
