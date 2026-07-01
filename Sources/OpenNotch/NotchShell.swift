import SwiftUI
import OpenNotchKit

struct NotchShell: View {
    let phase: NotchPhase
    let widgets: [PluginWidget]
    var body: some View {
        Group {
            if phase == .expanded {
                HStack(spacing: 16) { ForEach(widgets) { $0.content } }
                    .padding(16)
                    .background(.black, in: RoundedRectangle(cornerRadius: 20))
            } else {
                RoundedRectangle(cornerRadius: 12).fill(.black).frame(height: 32) // collapsed shape
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: phase)
    }
}
