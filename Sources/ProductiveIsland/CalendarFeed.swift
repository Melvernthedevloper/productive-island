import EventKit
import Observation

/// Today's remaining events from macOS Calendar (EventKit — Google accounts included). One permission prompt on first open.
@Observable @MainActor
final class CalendarFeed {
    var events: [EKEvent] = []       // next 8 days, sorted
    var authorized = false
    var today: [EKEvent] { events.filter { Calendar.current.isDateInToday($0.startDate) || $0.startDate < Date() } }
    var tomorrow: [EKEvent] { events.filter { Calendar.current.isDateInTomorrow($0.startDate) } }
    var week: [EKEvent] { events.filter { $0.startDate > Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400) } }
    private let store = EKEventStore()

    var next: EKEvent? { today.first }
    /// Minutes until the next event, or nil if none.
    func minutesToNext(at date: Date = Date()) -> Int? {
        guard let n = next else { return nil }
        return Int(n.startDate.timeIntervalSince(date) / 60)
    }

    init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        Task {
            authorized = (try? await store.requestFullAccessToEvents()) ?? false
            refresh()
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(60)); refresh() }
        }
    }

    func refresh() {
        guard authorized else { return }
        let now = Date()
        let end = Calendar.current.startOfDay(for: now).addingTimeInterval(8 * 86400)
        let pred = store.predicateForEvents(withStart: now.addingTimeInterval(-15 * 60), end: end, calendars: nil)
        events = store.events(matching: pred)
            .filter { !$0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
    }

    /// First URL in the event — Meet, Zoom, Teams links are all just URLs.
    nonisolated static func joinURL(_ e: EKEvent) -> URL? {
        if let u = e.url { return u }
        let text = [e.location, e.notes].compactMap { $0 }.joined(separator: " ")
        let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        return det?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))?.url
    }
}
