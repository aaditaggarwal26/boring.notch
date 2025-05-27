import EventKit
import SwiftUI
import Defaults
import Combine

// MARK: - Calendar Models

struct CalendarEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendar: EKCalendar
    let location: String?
    let notes: String?
    let url: URL?
    let attendees: [EKParticipant]?
    let status: EKEventStatus
    let availability: EKEventAvailability
    
    init(from ekEvent: EKEvent) {
        self.id = ekEvent.eventIdentifier
        self.title = ekEvent.title ?? "Untitled Event"
        self.startDate = ekEvent.startDate
        self.endDate = ekEvent.endDate
        self.isAllDay = ekEvent.isAllDay
        self.calendar = ekEvent.calendar
        self.location = ekEvent.location
        self.notes = ekEvent.notes
        self.url = ekEvent.url
        self.attendees = ekEvent.attendees
        self.status = ekEvent.status
        self.availability = ekEvent.availability
    }
    
    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }
    
    var isHappening: Bool {
        let now = Date()
        return now >= startDate && now <= endDate
    }
    
    var isUpcoming: Bool {
        startDate > Date()
    }
    
    var timeUntilStart: TimeInterval {
        startDate.timeIntervalSince(Date())
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: CalendarEvent, rhs: CalendarEvent) -> Bool {
        lhs.id == rhs.id
    }
}

struct CalendarGroup: Identifiable {
    let id = UUID()
    let title: String
    let events: [CalendarEvent]
    let date: Date
    
    var sortedEvents: [CalendarEvent] {
        events.sorted { $0.startDate < $1.startDate }
    }
}

enum CalendarError: LocalizedError {
    case accessDenied
    case accessRestricted
    case noCalendarsAvailable
    case eventStoreFailed
    case eventFetchFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Calendar access was denied. Please grant permission in System Settings."
        case .accessRestricted:
            return "Calendar access is restricted by system policies."
        case .noCalendarsAvailable:
            return "No calendars are available."
        case .eventStoreFailed:
            return "Failed to initialize calendar event store."
        case .eventFetchFailed(let message):
            return "Failed to fetch calendar events: \(message)"
        }
    }
}

// MARK: - CalendarManager

@MainActor
class CalendarManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var currentDate: Date = CalendarManager.startOfDay(Date()) {
        didSet {
            if !Calendar.current.isDate(currentDate, inSameDayAs: oldValue) {
                Logger.log("Current date changed to: \(currentDate)", category: .debug)
                Task {
                    await fetchEvents()
                }
            }
        }
    }
    
    @Published private(set) var events: [CalendarEvent] = [] {
        didSet {
            Logger.log("Events updated: \(events.count) events", category: .debug)
        }
    }
    
    @Published private(set) var groupedEvents: [CalendarGroup] = []
    @Published private(set) var allCalendars: [EKCalendar] = []
    @Published private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: CalendarError?
    @Published private(set) var selectedCalendars: [EKCalendar] = []
    
    // MARK: - Private Properties
    
    private let eventStore = EKEventStore()
    private var cancellables = Set<AnyCancellable>()
    private let fetchQueue = DispatchQueue(label: "CalendarManager.FetchQueue", qos: .userInitiated)
    private var eventFetchTask: Task<Void, Never>?
    
    // Caching
    private var eventsCache: [String: [CalendarEvent]] = [:]
    private var cacheExpiryTime: TimeInterval = 300 // 5 minutes
    private var lastCacheUpdate: Date = Date.distantPast
    
    // MARK: - Initialization
    
    init() {
        Logger.log("CalendarManager initializing", category: .lifecycle)
        
        setupObservers()
        checkCalendarAuthorization()
        
        Logger.log("CalendarManager initialized", category: .lifecycle)
    }
    
    deinit {
        Logger.log("CalendarManager deinitializing", category: .lifecycle)
        cleanup()
    }
    
    // MARK: - Setup Methods
    
    private func setupObservers() {
        // Monitor calendar selection changes
        $authorizationStatus
            .dropFirst()
            .sink { [weak self] status in
                Task { @MainActor in
                    await self?.handleAuthorizationChange(status)
                }
            }
            .store(in: &cancellables)
        
        // Monitor calendar defaults changes
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task {
                    await self?.updateSelectedCalendars()
                    await self?.fetchEvents()
                }
            }
            .store(in: &cancellables)
        
        // Monitor day changes
        NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.currentDate = CalendarManager.startOfDay(Date())
                }
            }
            .store(in: &cancellables)
        
        // Monitor event store changes
        NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task {
                    await self?.handleEventStoreChanged()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Authorization Management
    
    func checkCalendarAuthorization() {
        let status = EKEventStore.authorizationStatus(for: .event)
        
        Logger.log("Calendar authorization status: \(status)", category: .debug)
        authorizationStatus = status
        
        switch status {
        case .authorized, .fullAccess:
            Task {
                await loadCalendars()
                await updateSelectedCalendars()
                await fetchEvents()
            }
        case .notDetermined:
            requestCalendarAccess()
        case .denied, .restricted:
            handleAccessDenied(status)
        case .writeOnly:
            Logger.log("Calendar access is write-only", category: .warning)
        @unknown default:
            Logger.log("Unknown authorization status", category: .error)
        }
    }
    
    private func requestCalendarAccess() {
        Logger.log("Requesting calendar access", category: .lifecycle)
        
        eventStore.requestFullAccessToEvents { [weak self] granted, error in
            Task { @MainActor in
                if let error = error {
                    Logger.log("Calendar access error: \(error.localizedDescription)", category: .error)
                    self?.lastError = .eventFetchFailed(error.localizedDescription)
                }
                
                self?.authorizationStatus = granted ? .fullAccess : .denied
                
                if granted {
                    Logger.log("Calendar access granted", category: .success)
                    await self?.loadCalendars()
                    await self?.updateSelectedCalendars()
                    await self?.fetchEvents()
                } else {
                    Logger.log("Calendar access denied", category: .warning)
                    self?.lastError = .accessDenied
                }
            }
        }
    }
    
    private func handleAccessDenied(_ status: EKAuthorizationStatus) {
        let error: CalendarError = status == .denied ? .accessDenied : .accessRestricted
        lastError = error
        Logger.log("Calendar access denied or restricted", category: .warning)
    }
    
    private func handleAuthorizationChange(_ status: EKAuthorizationStatus) async {
        switch status {
        case .authorized, .fullAccess:
            await loadCalendars()
            await updateSelectedCalendars()
            await fetchEvents()
        case .denied, .restricted:
            events = []
            groupedEvents = []
            selectedCalendars = []
        default:
            break
        }
    }
    
    // MARK: - Calendar Management
    
    private func loadCalendars() async {
        Logger.log("Loading available calendars", category: .debug)
        
        let calendars = eventStore.calendars(for: .event)
        
        await MainActor.run {
            self.allCalendars = calendars.sorted { $0.title < $1.title }
            Logger.log("Loaded \(calendars.count) calendars", category: .success)
        }
    }
    
    private func updateSelectedCalendars() async {
        let newSelectedCalendars = allCalendars.filter { getCalendarSelected($0) }
        
        await MainActor.run {
            if self.selectedCalendars != newSelectedCalendars {
                self.selectedCalendars = newSelectedCalendars
                Logger.log("Selected calendars updated: \(newSelectedCalendars.count) calendars", category: .debug)
            }
        }
    }
    
    func getCalendarSelected(_ calendar: EKCalendar) -> Bool {
        switch Defaults[.calendarSelectionState] {
        case .all:
            return true
        case .selected(let identifiers):
            return identifiers.contains(calendar.calendarIdentifier)
        }
    }
    
    func setCalendarSelected(_ calendar: EKCalendar, isSelected: Bool) {
        Logger.log("Setting calendar '\(calendar.title)' selected: \(isSelected)", category: .debug)
        
        var selectionState = Defaults[.calendarSelectionState]
        
        switch selectionState {
        case .all:
            if !isSelected {
                let identifiers = Set(allCalendars.map { $0.calendarIdentifier }).subtracting([calendar.calendarIdentifier])
                selectionState = .selected(identifiers)
            }
        case .selected(var identifiers):
            if isSelected {
                identifiers.insert(calendar.calendarIdentifier)
            } else {
                identifiers.remove(calendar.calendarIdentifier)
            }
            
            selectionState = identifiers.count == allCalendars.count ? .all : .selected(identifiers)
        }
        
        Defaults[.calendarSelectionState] = selectionState
        
        Task {
            await updateSelectedCalendars()
            await fetchEvents()
        }
    }
    
    // MARK: - Event Fetching
    
    func fetchEvents() async {
        guard !isLoading else {
            Logger.log("Event fetch already in progress", category: .debug)
            return
        }
        
        guard authorizationStatus == .authorized || authorizationStatus == .fullAccess else {
            Logger.log("Cannot fetch events - unauthorized", category: .warning)
            return
        }
        
        guard !selectedCalendars.isEmpty else {
            await MainActor.run {
                self.events = []
                self.groupedEvents = []
            }
            return
        }
        
        await MainActor.run {
            isLoading = true
            lastError = nil
        }
        
        eventFetchTask?.cancel()
        eventFetchTask = Task {
            do {
                let fetchedEvents = try await performEventFetch()
                
                await MainActor.run {
                    if !Task.isCancelled {
                        self.events = fetchedEvents
                        self.groupedEvents = self.groupEventsByDate(fetchedEvents)
                        self.updateCache(fetchedEvents)
                    }
                }
            } catch {
                await MainActor.run {
                    if !Task.isCancelled {
                        Logger.log("Event fetch failed: \(error.localizedDescription)", category: .error)
                        self.lastError = .eventFetchFailed(error.localizedDescription)
                    }
                }
            }
            
            await MainActor.run {
                if !Task.isCancelled {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func performEventFetch() async throws -> [CalendarEvent] {
        return try await withCheckedThrowingContinuation { continuation in
            fetchQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: CalendarError.eventStoreFailed)
                    return
                }
                
                do {
                    let events = try self.fetchEventsSync()
                    continuation.resume(returning: events)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func fetchEventsSync() throws -> [CalendarEvent] {
        let calendar = Calendar.current
        let startOfDay = CalendarManager.startOfDay(currentDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? Date()
        
        Logger.log("Fetching events from \(startOfDay) to \(endOfDay)", category: .debug)
        
        // Check cache first
        let cacheKey = "\(startOfDay.timeIntervalSince1970)"
        if let cachedEvents = getCachedEvents(for: cacheKey) {
            Logger.log("Using cached events: \(cachedEvents.count) events", category: .debug)
            return cachedEvents
        }
        
        let predicate = eventStore.predicateForEvents(
            withStart: startOfDay,
            end: endOfDay,
            calendars: selectedCalendars
        )
        
        let ekEvents = eventStore.events(matching: predicate)
        let calendarEvents = ekEvents.map { CalendarEvent(from: $0) }
        
        Logger.log("Fetched \(calendarEvents.count) events from EventKit", category: .success)
        
        return calendarEvents.sorted { $0.startDate < $1.startDate }
    }
    
    // MARK: - Event Grouping
    
    private func groupEventsByDate(_ events: [CalendarEvent]) -> [CalendarGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: events) { event in
            calendar.startOfDay(for: event.startDate)
        }
        
        return grouped.compactMap { (date, events) in
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            
            return CalendarGroup(
                title: formatter.string(from: date),
                events: events,
                date: date
            )
        }.sorted { $0.date < $1.date }
    }
    
    // MARK: - Caching
    
    private func getCachedEvents(for key: String) -> [CalendarEvent]? {
        guard Date().timeIntervalSince(lastCacheUpdate) < cacheExpiryTime else {
            eventsCache.removeAll()
            return nil
        }
        
        return eventsCache[key]
    }
    
    private func updateCache(_ events: [CalendarEvent]) {
        let cacheKey = "\(CalendarManager.startOfDay(currentDate).timeIntervalSince1970)"
        eventsCache[cacheKey] = events
        lastCacheUpdate = Date()
        
        // Clean old cache entries
        let expiredKeys = eventsCache.keys.filter { key in
            guard let timestamp = TimeInterval(key) else { return true }
            return Date().timeIntervalSince1970 - timestamp > cacheExpiryTime
        }
        
        for key in expiredKeys {
            eventsCache.removeValue(forKey: key)
        }
    }
    
    // MARK: - Event Store Change Handling
    
    private func handleEventStoreChanged() async {
        Logger.log("Event store changed, refreshing data", category: .lifecycle)
        
        await loadCalendars()
        await updateSelectedCalendars()
        
        // Clear cache to force fresh fetch
        eventsCache.removeAll()
        
        await fetchEvents()
    }
    
    // MARK: - Date Management
    
    static func startOfDay(_ date: Date) -> Date {
        return Calendar.current.startOfDay(for: date)
    }
    
    func updateCurrentDate(_ date: Date) {
        Logger.log("Updating current date to: \(date)", category: .debug)
        currentDate = Calendar.current.startOfDay(for: date)
    }
    
    func goToNextDay() {
        guard let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: currentDate) else { return }
        updateCurrentDate(nextDay)
    }
    
    func goToPreviousDay() {
        guard let previousDay = Calendar.current.date(byAdding: .day, value: -1, to: currentDate) else { return }
        updateCurrentDate(previousDay)
    }
    
    func goToToday() {
        updateCurrentDate(Date())
    }
    
    // MARK: - Public Utility Methods
    
    func getEventsForTimeRange(start: Date, end: Date) -> [CalendarEvent] {
        return events.filter { event in
            event.startDate < end && event.endDate > start
        }
    }
    
    func getCurrentEvents() -> [CalendarEvent] {
        let now = Date()
        return events.filter { $0.isHappening }
    }
    
    func getUpcomingEvents(limit: Int = 5) -> [CalendarEvent] {
        return events
            .filter { $0.isUpcoming }
            .prefix(limit)
            .map { $0 }
    }
    
    func getEventById(_ id: String) -> CalendarEvent? {
        return events.first { $0.id == id }
    }
    
    func refreshEvents() {
        Logger.log("Manual event refresh requested", category: .debug)
        eventsCache.removeAll()
        
        Task {
            await fetchEvents()
        }
    }
    
    // MARK: - Error Handling
    
    func clearError() {
        lastError = nil
    }
    
    func retryLastOperation() {
        clearError()
        
        if authorizationStatus == .notDetermined {
            requestCalendarAccess()
        } else {
            Task {
                await fetchEvents()
            }
        }
    }
    
    // MARK: - Cleanup
    
    private func cleanup() {
        eventFetchTask?.cancel()
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        eventsCache.removeAll()
        
        Logger.log("CalendarManager cleanup completed", category: .lifecycle)
        Logger.trackMemory()
    }
}

// MARK: - Convenience Extensions

extension CalendarManager {
    
    var hasEvents: Bool {
        !events.isEmpty
    }
    
    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .fullAccess
    }
    
    var canRequestAccess: Bool {
        authorizationStatus == .notDetermined
    }
    
    var shouldShowSettings: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }
}

// MARK: - SwiftUI Helpers

extension CalendarManager {
    
    func eventColor(for event: CalendarEvent) -> Color {
        Color(event.calendar.cgColor)
    }
    
    func formatEventTime(_ event: CalendarEvent) -> String {
        if event.isAllDay {
            return "All Day"
        }
        
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        
        if Calendar.current.isDate(event.startDate, inSameDayAs: event.endDate) {
            return "\(formatter.string(from: event.startDate)) - \(formatter.string(from: event.endDate))"
        } else {
            formatter.dateStyle = .short
            return "\(formatter.string(from: event.startDate)) - \(formatter.string(from: event.endDate))"
        }
    }
    
    func eventStatusText(for event: CalendarEvent) -> String {
        if event.isHappening {
            return "Happening now"
        } else if event.isUpcoming {
            let timeInterval = event.timeUntilStart
            if timeInterval < 3600 { // Less than 1 hour
                let minutes = Int(timeInterval / 60)
                return "In \(minutes) minutes"
            } else if timeInterval < 86400 { // Less than 1 day
                let hours = Int(timeInterval / 3600)
                return "In \(hours) hour\(hours == 1 ? "" : "s")"
            } else {
                let days = Int(timeInterval / 86400)
                return "In \(days) day\(days == 1 ? "" : "s")"
            }
        } else {
            return "Past event"
        }
    }
}

// MARK: - Debug Extensions

#if DEBUG
extension CalendarManager {
    
    func debugPrintState() {
        print("""
        CalendarManager Debug State:
        - Authorization: \(authorizationStatus)
        - All Calendars: \(allCalendars.count)
        - Selected Calendars: \(selectedCalendars.count)
        - Events: \(events.count)
        - Current Date: \(currentDate)
        - Is Loading: \(isLoading)
        - Cache Size: \(eventsCache.count)
        - Last Error: \(lastError?.localizedDescription ?? "None")
        """)
    }
    
    func createTestEvents() -> [CalendarEvent] {
        // Create mock events for testing
        let calendar = Calendar.current
        let now = Date()
        
        var testEvents: [CalendarEvent] = []
        
        // Add events at different times
        for i in 0..<5 {
            if let eventDate = calendar.date(byAdding: .hour, value: i, to: now),
               let endDate = calendar.date(byAdding: .hour, value: i + 1, to: now) {
                
                let mockEvent = EKEvent(eventStore: eventStore)
                mockEvent.title = "Test Event \(i + 1)"
                mockEvent.startDate = eventDate
                mockEvent.endDate = endDate
                mockEvent.calendar = allCalendars.first ?? eventStore.defaultCalendarForNewEvents
                
                testEvents.append(CalendarEvent(from: mockEvent))
            }
        }
        
        return testEvents
    }
}
#endif