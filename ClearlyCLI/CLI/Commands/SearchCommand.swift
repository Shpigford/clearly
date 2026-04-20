import ArgumentParser
import ClearlyCore
import Foundation

struct SearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Full-text search across loaded vaults. Emits NDJSON hits (one per line) in JSON mode.",
        discussion: """
        Uses the vault's FTS5 index (BM25 ranking). Each hit includes the
        vault, relative path, filename, a matches_filename flag, and a few
        context excerpts. Output is NDJSON — one hit per line — which
        composes well with jq / xargs.

        Output shape documented in README.md, section "clearly CLI" →
        "Tool reference" → search_notes.

        EXAMPLES
          # Basic search
          clearly search pricing

          # Cap results and pretty-print one hit:
          clearly search "API design" --limit 5 | head -1 | jq .

          # Pipeline: list paths of the top 20 matches
          clearly search rust --limit 20 | jq -r '.relative_path'

          # Combine with --in-vault via read (search searches all vaults):
          clearly search budget | jq -r '.relative_path' | xargs -I{} clearly read {}
        """
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
                message: "Unable to open any vault index: \(error.localizedDescription)",
                extra: ["bundle_id": globals.bundleID]
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
