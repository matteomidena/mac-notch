import Foundation

/// Height of the open notch on the Agents tab: it grows with the rows, between today's 300 and a cap.
public enum AgentsLayout {
    public static let rowHeight: CGFloat = 32
    public static let minHeight: CGFloat = 300
    public static let maxHeight: CGFloat = 480

    /// Everything that isn't a row, worst case:
    /// top inset 38 (tallest notch) + content padding 4 top / 10 bottom + limits header 35
    /// (9 + 9 padding around a ~17 pt 14 pt line) + 8 spacing between the two panels
    /// + 10 for the flagged session row, which grows to 42 because of its Stop keycap = 105.
    /// The 1 pt panel borders are strokes drawn inside the panels, so they add nothing.
    static let chrome: CGFloat = 38 + 4 + 10 + 35 + 8 + 10

    public static func panelHeight(limitRows: Int, sessionRows: Int) -> CGFloat {
        min(maxHeight, max(minHeight, chrome + rowHeight * CGFloat(limitRows + sessionRows)))
    }
}
