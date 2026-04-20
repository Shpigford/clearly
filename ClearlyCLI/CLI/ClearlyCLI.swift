import ArgumentParser
import ClearlyCore
import Foundation

@main
struct ClearlyCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clearly",
        abstract: "Clearly CLI + Model Context Protocol stdio server.",
        subcommands: [
            MCPCommand.self,
            SearchCommand.self,
            ReadCommand.self,
            ListCommand.self,
            HeadingsCommand.self,
            FrontmatterCommand.self,
            BacklinksCommand.self,
            TagsCommand.self,
            CreateCommand.self,
            UpdateCommand.self,
            VaultsCommand.self,
            IndexCommand.self,
        ]
    )
}
