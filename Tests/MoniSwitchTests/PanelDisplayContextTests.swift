import Testing
@testable import MoniSwitch

struct PanelDisplayContextTests {
    private func displays() -> [DisplayInfo] {
        DisplayManager.shared.parseList(DisplayListParserTests.dualScreenFixture)
    }

    @Test func selectionSurvivesRefreshAndFallsBackAfterDisconnect() throws {
        let list = displays()
        let main = try #require(list.first(where: { $0.isMain }))
        let other = try #require(list.first(where: { !$0.isMain }))
        #expect(PanelDisplayContext.selectedID(preferred: nil, in: list) == main.id)
        #expect(PanelDisplayContext.selectedID(preferred: other.id, in: list) == other.id)
        #expect(PanelDisplayContext.selectedID(preferred: other.id, in: [main]) == main.id)
        #expect(PanelDisplayContext.selectedID(preferred: main.id, in: []) == nil)
        #expect(PanelDisplayContext.selectedID(preferred: nil, in: [other]) == other.id)
    }

    @Test func duplicateNamesStayDistinctWhenListOrderChanges() throws {
        var a = try #require(displays().first)
        var b = a
        a.id = "A"
        b.id = "B"
        #expect(PanelDisplayContext.name(for: a, in: [a, b], baseName: "Display") == "Display (1)")
        #expect(PanelDisplayContext.name(for: b, in: [b, a], baseName: "Display") == "Display (2)")
    }

    @Test func modeChangesInvalidateMenusEvenWhenDisplayIdentityIsUnchanged() throws {
        var display = try #require(displays().first)
        let original = PanelDisplayContext.configurationID([display])
        display.resolution = (1280, 720)
        #expect(PanelDisplayContext.configurationID([display]) != original)
    }

    @Test func viewportNeverExceedsAvailableSpace() {
        #expect(PanelDisplayContext.viewportHeight(content: 250, available: 600) == 250)
        #expect(PanelDisplayContext.viewportHeight(content: 1400, available: 500) == 500)
        #expect(PanelDisplayContext.viewportHeight(content: 0, available: 500) == 1)
    }
}
