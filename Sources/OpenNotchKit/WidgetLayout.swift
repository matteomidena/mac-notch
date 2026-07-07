/// A widget placed on the expanded panel's grid.
public struct LaidOutWidget: Equatable {
    public let id: String
    public let row: Int
    public let column: Int
    public let columnSpan: Int
    public init(id: String, row: Int, column: Int, columnSpan: Int) {
        self.id = id; self.row = row; self.column = column; self.columnSpan = columnSpan
    }
}

/// Pure grid packing for the expanded panel. No geometry — the view maps
/// (row, column, span) to points. Input order is the user's widget order.
public enum WidgetLayout {
    private static func span(_ s: WidgetSize, columns: Int) -> Int {
        switch s {
        case .wide: return columns
        case .medium: return min(2, columns)
        case .small: return 1
        }
    }

    public static func arrange(_ widgets: [(id: String, size: WidgetSize)], columns: Int) -> [LaidOutWidget] {
        guard columns > 0 else { return [] }
        var out: [LaidOutWidget] = []
        var row = 0, col = 0
        for w in widgets {
            let s = span(w.size, columns: columns)
            if col + s > columns {          // doesn't fit → wrap
                row += 1; col = 0
            }
            out.append(LaidOutWidget(id: w.id, row: row, column: col, columnSpan: s))
            col += s
            if col >= columns { row += 1; col = 0 }
        }
        return out
    }
}
