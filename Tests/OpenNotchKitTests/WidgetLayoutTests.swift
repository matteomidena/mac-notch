import Testing
@testable import OpenNotchKit

@Test func wideWidgetSpansAllColumns() {
    let out = WidgetLayout.arrange([("media", .wide)], columns: 4)
    #expect(out == [LaidOutWidget(id: "media", row: 0, column: 0, columnSpan: 4)])
}

@Test func smallWidgetsPackLeftToRightThenWrap() {
    let out = WidgetLayout.arrange(
        [("a", .small), ("b", .small), ("c", .small)], columns: 2)
    #expect(out == [
        LaidOutWidget(id: "a", row: 0, column: 0, columnSpan: 1),
        LaidOutWidget(id: "b", row: 0, column: 1, columnSpan: 1),
        LaidOutWidget(id: "c", row: 1, column: 0, columnSpan: 1),
    ])
}

@Test func mediumThatDoesNotFitWraps() {
    let out = WidgetLayout.arrange(
        [("a", .small), ("b", .medium)], columns: 2)
    // 'a' takes col 0; 'b' needs span 2 but only 1 left → wraps to row 1.
    #expect(out == [
        LaidOutWidget(id: "a", row: 0, column: 0, columnSpan: 1),
        LaidOutWidget(id: "b", row: 1, column: 0, columnSpan: 2),
    ])
}
