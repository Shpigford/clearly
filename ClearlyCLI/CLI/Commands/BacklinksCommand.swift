import ArgumentParser
import Foundation

struct BacklinksCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "backlinks",
        abstract: "List wiki-link references and unlinked mentions pointing to a note."
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Vault-relative path (e.g. 'folder/My Note.md') or bare filename.")
    var relativePath: String

    @Option(name: .customLong("in-vault"), help: "Optional vault disambiguator (name or path) when multiple vaults are loaded.")
    var inVault: String?

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
            let result = try await getBacklinks(
                GetBacklinksArgs(relativePath: relativePath, vault: inVault),
                vaults: vaults
            )
            switch globals.format {
            case .json:
                try Emitter.emit(result, format: .json)
            case .text:
                Emitter.emitLine("# Backlinks for: \(result.relativePath) (\(result.vault))")
                Emitter.emitLine("")
                Emitter.emitLine("## Linked (\(result.linked.count))")
                if result.linked.isEmpty {
                    Emitter.emitLine("  (none)")
                } else {
                    for link in result.linked {
                        let line = link.lineNumber.map { " L\($0)" } ?? ""
                        Emitter.emitLine("  \(link.relativePath)\(line)")
                    }
                }
                Emitter.emitLine("")
                Emitter.emitLine("## Unlinked (\(result.unlinked.count))")
                if result.unlinked.isEmpty {
                    Emitter.emitLine("  (none)")
                } else {
                    for mention in result.unlinked {
                        Emitter.emitLine("  \(mention.relativePath) L\(mention.lineNumber): \(mention.contextLine)")
                    }
                }
            }
        } catch let error as ToolError {
            let code = Emitter.emitToolError(error)
            throw ExitCode(code)
        }
    }
}
