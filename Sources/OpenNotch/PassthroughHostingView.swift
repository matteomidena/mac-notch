import AppKit
import SwiftUI

/// Hosting view for the oversized static panel. Mouse events outside the
/// visible notch shape fall through to whatever is behind the transparent
/// window region; file drags over the shape report in/out for the FSM.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    /// Whether a point (this view's coordinate space) is inside the interactive
    /// region — full footprint below the menubar, notch-width within it.
    var interactiveContains: (NSPoint) -> Bool = { _ in false }
    var onDragChange: ((Bool) -> Void)?
    private var dragInside = false

    required init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
    }

    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` is in the superview's coordinate space.
        let local = convert(point, from: superview)
        guard interactiveContains(local) else { return nil }
        return super.hitTest(point)
    }

    // M2 only expands on drag-hover; dropping is M4 (shelf). Return [] so the
    // drag is not accepted anywhere yet.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDrag(sender)
        return []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDrag(sender)
        return []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        if dragInside { dragInside = false; onDragChange?(false) }
    }

    private func updateDrag(_ sender: NSDraggingInfo) {
        let inside = interactiveContains(convert(sender.draggingLocation, from: nil))
        if inside != dragInside {
            dragInside = inside
            onDragChange?(inside)
        }
    }
}
