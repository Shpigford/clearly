import ArgumentParser
import Foundation

struct SearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Full-text search across loaded vaults. Emits NDJSON hits (one per line) in JSON mode."
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Search query. Supports quoted phrases for exact match.")
    var query: String

    @Option(help: "Max results to return. Default 20, capped at 100.")
    var limit: Int?

    func run() async throws {
        let vaults: [LoadedVault]
        do {
            vaults = try IndexSet.openIndexes(globals)
        } catch {
            Emitter.emitError(
                "no_vaults",
                message: "Unable to open any vault index: \(error.localizedDescription)"
            )
            throw ExitCode(Exit.general)
        }

        do {
            let result = try await searchNotes(
                SearchNotesArgs(query: query, limit: limit),
                vaults: vaults
            )
            switch globals.format {
            case .json:
                for hit in result.results {
                    try Emitter.emitNDJSONRecord(hit)
                }
            case .text:
                for hit in result.results {
                    let tag = hit.matchesFilename ? " [filename]" : ""
                    Emitter.emitLine("\(hit.relativePath)\t\(hit.filename)\(tag)")
                    for excerpt in hit.excerpts {
                        Emitter.emitLine("  L\(excerpt.lineNumber): \(excerpt.contextLine)")
                    }
                }
            }
        } catch let error as ToolError {
            let code = Emitter.emitToolError(error)
            throw ExitCode(code)
        }
    }
}
