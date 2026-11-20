import Foundation
import Testing
@testable import ClearlyCore

struct NoteTemplateTests {

    private func makeNow() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = DateComponents(
            calendar: calendar,
            timeZone: .current,
            year: 2026,
            month: 11,
            day: 20,
            hour: 15,
            minute: 4
        )
        return components.date!
    }

    private func makeTempVault() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func listMissingFolderReturnsEmpty() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }

        let templates = NoteTemplateEngine.list(in: root)
        #expect(templates.isEmpty)
    }

    @Test func listReadsTopLevelMarkdownSortedByName() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let templatesDir = root.appendingPathComponent(NoteTemplateEngine.folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: templatesDir, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: templatesDir.appendingPathComponent("Project.md").path,
            contents: Data("# p".utf8)
        )
        FileManager.default.createFile(
            atPath: templatesDir.appendingPathComponent("abstract.md").path,
            contents: Data("# a".utf8)
        )

        let names = NoteTemplateEngine.list(in: root).map(\.name)
        #expect(names == ["abstract", "Project"])
    }

    @Test func listSkipsHiddenAndNestedFiles() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let templatesDir = root.appendingPathComponent(NoteTemplateEngine.folderName, isDirectory: true)
        let nested = templatesDir.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: templatesDir.appendingPathComponent("Project.md").path,
            contents: Data("# p".utf8)
        )
        FileManager.default.createFile(
            atPath: templatesDir.appendingPathComponent("abstract.md").path,
            contents: Data("# a".utf8)
        )
        FileManager.default.createFile(
            atPath: templatesDir.appendingPathComponent(".hidden.md").path,
            contents: Data("# h".utf8)
        )
        FileManager.default.createFile(
            atPath: nested.appendingPathComponent("x.md").path,
            contents: Data("# x".utf8)
        )

        let names = NoteTemplateEngine.list(in: root).map(\.name)
        #expect(names == ["abstract", "Project"])
    }

    @Test func renderSubstitutesDateTimeTitle() {
        let rendered = NoteTemplateEngine.render(
            template: "# {{title}}\n{{date}} {{time}}\n",
            title: "Hash Map",
            now: makeNow(),
            existingText: ""
        )
        #expect(rendered.combined.contains("# Hash Map"))
        #expect(rendered.combined.contains("2026-11-20"))
        #expect(rendered.combined.contains("15:04"))
    }

    @Test func renderStripsDataviewJSFence() {
        let template = """
        # задачи из now
        ```dataviewjs
        const currentFile = dv.current().file.name;
        dv.table(["Заметка"], pages.map(p => [p.file.link]));
        ```

        ### to-do list
        """
        let rendered = NoteTemplateEngine.render(
            template: template,
            title: "Daily",
            now: makeNow(),
            existingText: ""
        )
        #expect(rendered.combined.contains("# задачи из now"))
        #expect(rendered.combined.contains("### to-do list"))
        #expect(!rendered.combined.contains("dataviewjs"))
        #expect(!rendered.combined.contains("dv."))
        #expect(!rendered.combined.contains("dv.table"))
    }

    @Test func renderStripsQuotedDataviewCallouts() {
        let template = """
        #project
        - [ ] {{title}}

        # Todo List
        > [!todo] Active
        > ```dataview
        >  task
        >  from [[]]
        >  where !completed
        > sort file.ctime desc
        > ```

        > [!todo] Completed
        > ```dataview
        >  task
        > from [[]]
        >  where completed
        >   sort file.ctime desc
        >   limit 10
        > ```

        # Links
        """
        let rendered = NoteTemplateEngine.render(
            template: template,
            title: "Ship",
            now: makeNow(),
            existingText: ""
        )
        #expect(rendered.combined.contains("# Todo List"))
        #expect(!rendered.combined.contains("[!todo]"))
        #expect(!rendered.combined.lowercased().contains("dataview"))
        #expect(!rendered.combined.contains("where !completed"))
    }

    @Test func renderJoinsWithBlankLineWhenExistingNonEmpty() {
        let rendered = NoteTemplateEngine.render(
            template: "# T\n",
            title: "T",
            now: makeNow(),
            existingText: "body"
        )
        #expect(rendered.combined == "# T\n\nbody")
        #expect(rendered.prefix == "# T\n\n")
    }

    @Test func renderKeepsTemplateOnlyWhenExistingEmpty() {
        let template = "# T\n"
        let rendered = NoteTemplateEngine.render(
            template: template,
            title: "T",
            now: makeNow(),
            existingText: ""
        )
        #expect(rendered.combined == "# T\n")
        #expect(rendered.prefix == "# T\n")
    }

    @Test func renderPrependsEvenWhenExistingStartsWithTemplate() {
        let rendered = NoteTemplateEngine.render(
            template: "# T\n",
            title: "T",
            now: makeNow(),
            existingText: "# T\n\n"
        )
        #expect(rendered.combined == "# T\n\n# T\n\n")
    }
}
