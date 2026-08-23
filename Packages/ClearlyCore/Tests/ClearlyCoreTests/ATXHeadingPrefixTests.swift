import Testing
@testable import ClearlyCore

struct ATXHeadingPrefixTests {
    @Test func recognizesEveryHeadingLevel() {
        for level in 1...6 {
            let marker = String(repeating: "#", count: level)
            #expect(ATXHeadingPrefix.parse(in: "\(marker) Heading") == "\(marker) ")
        }
    }

    @Test func includesTheCompleteSpaceOrTabSeparator() {
        #expect(ATXHeadingPrefix.parse(in: "##   Heading") == "##   ")
        #expect(ATXHeadingPrefix.parse(in: "##\tHeading") == "##\t")
        #expect(ATXHeadingPrefix.parse(in: "# \t Heading") == "# \t ")
    }

    @Test func recognizesAHeadingBeforeContentIsTyped() {
        #expect(ATXHeadingPrefix.parse(in: "# ") == "# ")
        #expect(ATXHeadingPrefix.parse(in: "###\t") == "###\t")
    }

    @Test func rejectsNonHeadingPrefixes() {
        #expect(ATXHeadingPrefix.parse(in: "#") == nil)
        #expect(ATXHeadingPrefix.parse(in: "####### Heading") == nil)
        #expect(ATXHeadingPrefix.parse(in: " # Heading") == nil)
        #expect(ATXHeadingPrefix.parse(in: "#not-a-heading") == nil)
        #expect(ATXHeadingPrefix.parse(in: "") == nil)
    }
}
