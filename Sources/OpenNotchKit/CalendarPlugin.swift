import AppKit
import EventKit
import SwiftUI

/// Built-in Calendar tab: a day strip and that day's events, read from macOS Calendar
/// (every account the user added there: iCloud, Google, Exchange…). Layout after boring.notch.
@MainActor public struct CalendarPlugin: NotchPlugin, NotchTabProvider {
    public static let manifest = PluginManifest(
        id: "cafe.notch.calendar", name: "Calendar", version: "1.0.0", author: "OpenNotch")
    private let store = CalendarStore()
    public init(host: PluginHost) {}
    public func widgets() -> [PluginWidget] { [] }
    public func tabs() -> [PluginTab] {
        [PluginTab(id: "calendar", title: "Calendar", systemImage: "calendar",
                   content: AnyView(CalendarTabView(store: store)))]
    }
}

@MainActor @Observable final class CalendarStore {
    private let ek = EKEventStore()
    private(set) var status = EKEventStore.authorizationStatus(for: .event)
    private(set) var events: [EKEvent] = []
    private var day = Calendar.current.startOfDay(for: .now)
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        // Edits in Calendar.app, or a sync, land here without reopening the tab.
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    var hasAccess: Bool { status == .fullAccess }

    func requestAccess() async {
        _ = try? await ek.requestFullAccessToEvents()
        reload()
    }

    func show(_ date: Date) {
        day = Calendar.current.startOfDay(for: date)
        reload()
    }

    private func reload() {
        // Re-read every time: access can be granted in System Settings while we run.
        status = EKEventStore.authorizationStatus(for: .event)
        guard hasAccess, let end = Calendar.current.date(byAdding: .day, value: 1, to: day) else { events = []; return }
        events = ek.events(matching: ek.predicateForEvents(withStart: day, end: end, calendars: nil))
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
    }
}

struct CalendarTabView: View {
    let store: CalendarStore
    @State private var selected = Calendar.current.startOfDay(for: .now)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(selected.formatted(.dateTime.month(.abbreviated)))
                        .font(Hex.text(16, weight: .semibold)).foregroundStyle(Hex.ink)
                    Text(selected.formatted(.dateTime.year()))
                        .font(Hex.text(12)).foregroundStyle(Hex.muted)
                }
                .frame(width: 44, alignment: .leading)
                .contentTransition(.numericText())
                DayStrip(selected: $selected)
            }
            Group {
                if store.hasAccess { events } else { accessPrompt }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 6)
        .onAppear {
            selected = Calendar.current.startOfDay(for: .now)
            store.show(selected)
        }
        .onChange(of: selected) { store.show(selected) }
    }

    @ViewBuilder private var events: some View {
        if store.events.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "calendar.badge.checkmark").font(.system(size: 18)).foregroundStyle(Hex.muted)
                Text(Calendar.current.isDateInToday(selected) ? "No events today" : "No events")
                    .font(Hex.text(12.5)).foregroundStyle(Hex.muted)
            }
            .frame(maxWidth: .infinity).padding(.top, 14)
            .transition(.opacity)
        } else {
            ScrollView {
                VStack(spacing: 2) { ForEach(store.events, id: \.calendarItemIdentifier) { EventRow(event: $0) } }
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
            .id(selected)  // the list cross-fades when the day changes
            .transition(.opacity.combined(with: .offset(y: 6)))
        }
    }

    @ViewBuilder private var accessPrompt: some View {
        let denied = store.status == .denied || store.status == .restricted
        VStack(spacing: 8) {
            Text(denied ? "Calendar access is off" : "See your events here")
                .font(Hex.text(12.5)).foregroundStyle(Hex.muted)
            Button {
                if denied {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                } else {
                    Task { await store.requestAccess() }
                }
            } label: {
                Text(denied ? "Open System Settings" : "Allow Calendar access")
                    .font(Hex.text(12, weight: .medium)).foregroundStyle(Hex.bg)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Hex.ink, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity).padding(.top, 10)
    }
}

/// Horizontal strip, 7 days back to 14 ahead; snaps the chosen day to the center.
private struct DayStrip: View {
    @Binding var selected: Date
    @State private var centered: Date?
    private let days: [Date] = {
        let cal = Calendar.current, today = cal.startOfDay(for: .now)
        return (-7...14).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
    }()

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(days, id: \.self) { day in
                    cell(day).id(day)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.never)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $centered, anchor: .center)
        .safeAreaPadding(.horizontal, 120)  // lets the first and last days reach the center
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                     .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
        .frame(height: 46)
        .onAppear { centered = selected }
        .onChange(of: selected) { if centered != selected { withAnimation(.snappy) { centered = selected } } }
        // Scrolling picks the day under the center, like a wheel.
        .onChange(of: centered) { if let centered, centered != selected { selected = centered } }
    }

    private func cell(_ day: Date) -> some View {
        let isSelected = Calendar.current.isDate(day, inSameDayAs: selected)
        let isToday = Calendar.current.isDateInToday(day)
        return Button { withAnimation(.snappy) { selected = day } } label: {
            VStack(spacing: 4) {
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(Hex.text(10.5)).foregroundStyle(isSelected ? Hex.ink : Hex.muted)
                Text(day.formatted(.dateTime.day()))
                    .font(Hex.text(13, weight: .medium))
                    .foregroundStyle(isToday ? Hex.bg : isSelected ? Hex.ink : Hex.muted)
                    .frame(width: 22, height: 22)
                    .background(isToday ? Hex.ink : .clear, in: Circle())
            }
            .frame(width: 30).padding(.vertical, 3)
            .background(isSelected ? Hex.line(0.10) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct EventRow: View {
    let event: EKEvent
    var body: some View {
        let ended = !event.isAllDay && event.endDate < .now
        HStack(spacing: 8) {
            Capsule().fill(Color(cgColor: event.calendar.cgColor)).frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title ?? "").font(Hex.text(12.5, weight: .medium)).foregroundStyle(Hex.ink).lineLimit(1)
                Text(timeText).font(Hex.mono(10)).foregroundStyle(Hex.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .opacity(ended ? 0.45 : 1)
    }

    private var timeText: String {
        if event.isAllDay { return "All day" }
        let t = Date.FormatStyle(date: .omitted, time: .shortened)
        return "\(event.startDate.formatted(t)) – \(event.endDate.formatted(t))"
    }
}
