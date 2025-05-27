import Combine
import Defaults
import SwiftUI
import TheBoringWorkerNotifier

// MARK: - Supporting Types

enum SneakContentType: String, CaseIterable {
    case brightness = "brightness"
    case volume = "volume"
    case backlight = "backlight"
    case music = "music"
    case mic = "mic"
    case battery = "battery"
    case download = "download"
    case notification = "notification"
    
    var displayName: String {
        switch self {
        case .brightness:
            return "Brightness"
        case .volume:
            return "Volume"
        case .backlight:
            return "Keyboard Backlight"
        case .music:
            return "Music"
        case .mic:
            return "Microphone"
        case .battery:
            return "Battery"
        case .download:
            return "Download"
        case .notification:
            return "Notification"
        }
    }
    
    var iconName: String {
        switch self {
        case .brightness:
            return "sun.max"
        case .volume:
            return "speaker.wave.3"
        case .backlight:
            return "keyboard"
        case .music:
            return "music.note"
        case .mic:
            return "mic"
        case .battery:
            return "battery.100"
        case .download:
            return "arrow.down.circle"
        case .notification:
            return "bell"
        }
    }
}

struct SneakPeek: Equatable {
    var show: Bool = false
    var type: SneakContentType = .music
    var value: CGFloat = 0
    var icon: String = ""
    var timestamp: Date = Date()
    var duration: TimeInterval = 1.5
    
    static func == (lhs: SneakPeek, rhs: SneakPeek) -> Bool {
        lhs.show == rhs.show &&
        lhs.type == rhs.type &&
        lhs.value == rhs.value &&
        lhs.icon == rhs.icon
    }
}

struct SharedSneakPeek: Codable {
    var show: Bool
    var type: String
    var value: String
    var icon: String
    var timestamp: TimeInterval
}

enum NotchViews: String, CaseIterable {
    case home = "home"
    case shelf = "shelf"
    case calendar = "calendar"
    case settings = "settings"
    
    var displayName: String {
        switch self {
        case .home:
            return "Home"
        case .shelf:
            return "Shelf"
        case .calendar:
            return "Calendar"
        case .settings:
            return "Settings"
        }
    }
    
    var iconName: String {
        switch self {
        case .home:
            return "house"
        case .shelf:
            return "tray"
        case .calendar:
            return "calendar"
        case .settings:
            return "gear"
        }
    }
}

// MARK: - BoringViewCoordinator

@MainActor
class BoringViewCoordinator: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = BoringViewCoordinator()
    
    // MARK: - Published Properties
    
    @Published var currentView: NotchViews = .home {
        didSet {
            if currentView != oldValue {
                Logger.log("Current view changed: \(oldValue.rawValue) -> \(currentView.rawValue)", category: .ui)
                saveViewState()
            }
        }
    }
    
    @Published var sneakPeek: SneakPeek = .init() {
        didSet {
            if sneakPeek != oldValue {
                handleSneakPeekChange()
            }
        }
    }
    
    @Published var optionKeyPressed: Bool = false
    
    @Published var selectedScreen: String = NSScreen.main?.localizedName ?? "Unknown" {
        didSet {
            if selectedScreen != oldValue {
                Logger.log("Selected screen changed: \(selectedScreen)", category: .ui)
                preferredScreen = selectedScreen
                NotificationCenter.default.post(name: Notification.Name.selectedScreenChanged, object: nil)
            }
        }
    }
    
    // MARK: - AppStorage Properties
    
    @AppStorage("firstLaunch") var firstLaunch: Bool = true {
        didSet {
            if !firstLaunch && oldValue {
                Logger.log("First launch completed", category: .lifecycle)
            }
        }
    }
    
    @AppStorage("showWhatsNew") var showWhatsNew: Bool = true
    @AppStorage("musicLiveActivity") var showMusicLiveActivityOnClosed: Bool = true
    @AppStorage("currentMicStatus") var currentMicStatus: Bool = true
    
    @AppStorage("alwaysShowTabs") var alwaysShowTabs: Bool = true {
        didSet {
            handleAlwaysShowTabsChange(oldValue: oldValue)
        }
    }
    
    @AppStorage("openLastTabByDefault") var openLastTabByDefault: Bool = false {
        didSet {
            if openLastTabByDefault {
                alwaysShowTabs = true
                restoreViewState()
            }
        }
    }
    
    @AppStorage("hudReplacement") var hudReplacement: Bool = true {
        didSet {
            notifier.postNotification(name: notifier.toggleHudReplacementNotification.name, userInfo: nil)
            Logger.log("HUD replacement: \(hudReplacement ? "enabled" : "disabled")", category: .debug)
        }
    }
    
    @AppStorage("preferred_screen_name") var preferredScreen = NSScreen.main?.localizedName ?? "Unknown"
    
    @AppStorage("lastActiveView") private var lastActiveViewRaw: String = NotchViews.home.rawValue
    
    // MARK: - Private Properties
    
    var notifier: TheBoringWorkerNotifier = .init()
    private var sneakPeekDispatch: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private let stateQueue = DispatchQueue(label: "com.boringnotch.coordinator", qos: .userInteractive)
    
    // MARK: - Computed Properties
    
    var lastActiveView: NotchViews {
        get {
            NotchViews(rawValue: lastActiveViewRaw) ?? .home
        }
        set {
            lastActiveViewRaw = newValue.rawValue
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        selectedScreen = preferredScreen
        notifier = TheBoringWorkerNotifier()
        
        Logger.log("BoringViewCoordinator initializing", category: .lifecycle)
        
        setupObservers()
        restoreViewState()
        
        Logger.log("BoringViewCoordinator initialized", category: .lifecycle)
    }
    
    // MARK: - Setup Methods
    
    private func setupObservers() {
        // Monitor screen changes
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.validateSelectedScreen()
            }
            .store(in: &cancellables)
        
        // Monitor option key state
        NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            let isOptionPressed = event.modifierFlags.contains(.option)
            if self?.optionKeyPressed != isOptionPressed {
                self?.optionKeyPressed = isOptionPressed
            }
            return event
        }
    }
    
    func setupWorkersNotificationObservers() {
        Logger.log("Setting up worker notification observers", category: .lifecycle)
        
        notifier.setupObserver(notification: notifier.micStatusNotification, handler: handleMicStatusNotification)
        notifier.setupObserver(notification: notifier.sneakPeakNotification, handler: handleSneakPeekNotification)
        
        Logger.log("Worker notification observers setup completed", category: .success)
    }
    
    // MARK: - Sneak Peek Management
    
    func toggleSneakPeek(
        status: Bool,
        type: SneakContentType,
        duration: TimeInterval = 1.5,
        value: CGFloat = 0,
        icon: String = ""
    ) {
        Logger.log("Toggling sneak peek: \(status) for \(type.displayName)", category: .ui)
        
        // Validate HUD replacement for non-music types
        if type != .music && !hudReplacement {
            Logger.log("HUD replacement disabled, ignoring sneak peek for \(type.displayName)", category: .debug)
            return
        }
        
        let newSneakPeek = SneakPeek(
            show: status,
            type: type,
            value: value,
            icon: icon.isEmpty ? type.iconName : icon,
            timestamp: Date(),
            duration: duration
        )
        
        withAnimation(.smooth) {
            self.sneakPeek = newSneakPeek
        }
        
        // Handle microphone status
        if type == .mic {
            currentMicStatus = value == 1
        }
    }
    
    private func handleSneakPeekChange() {
        if sneakPeek.show {
            sneakPeekDispatch?.cancel()
            
            sneakPeekDispatch = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                withAnimation(.smooth) {
                    self.toggleSneakPeek(status: false, type: .music)
                }
            }
            
            DispatchQueue.main.asyncAfter(
                deadline: .now() + sneakPeek.duration,
                execute: sneakPeekDispatch!
            )
        }
    }
    
    // MARK: - Notification Handlers
    
    @objc private func handleSneakPeekNotification(_ notification: Notification) {
        guard let data = notification.userInfo?.first?.value as? Data else {
            Logger.log("Invalid sneak peek notification data", category: .error)
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let decodedData = try decoder.decode(SharedSneakPeek.self, from: data)
            
            let contentType = SneakContentType(rawValue: decodedData.type) ?? .brightness
            let value = CGFloat((NumberFormatter().number(from: decodedData.value) ?? 0.0).floatValue)
            let icon = decodedData.icon
            
            Logger.log("Received sneak peek notification: \(contentType.displayName)", category: .debug)
            
            toggleSneakPeek(
                status: decodedData.show,
                type: contentType,
                value: value,
                icon: icon
            )
            
        } catch {
            Logger.log("Failed to decode sneak peek notification: \(error)", category: .error)
        }
    }
    
    @objc private func handleMicStatusNotification(_ notification: Notification) {
        guard let status = notification.userInfo?.first?.value as? Bool else {
            Logger.log("Invalid mic status notification", category: .error)
            return
        }
        
        currentMicStatus = status
        Logger.log("Mic status updated: \(status ? "unmuted" : "muted")", category: .debug)
    }
    
    // MARK: - View Management
    
    func navigateToView(_ view: NotchViews, animated: Bool = true) {
        Logger.log("Navigating to view: \(view.displayName)", category: .ui)
        
        if animated {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentView = view
            }
        } else {
            currentView = view
        }
    }
    
    func showEmpty() {
        navigateToView(.home)
    }
    
    private func saveViewState() {
        if openLastTabByDefault {
            lastActiveView = currentView
        }
    }
    
    private func restoreViewState() {
        if openLastTabByDefault {
            currentView = lastActiveView
            Logger.log("Restored view state: \(currentView.displayName)", category: .debug)
        }
    }
    
    private func handleAlwaysShowTabsChange(oldValue: Bool) {
        if !alwaysShowTabs {
            openLastTabByDefault = false
            if shouldNavigateToHome() {
                navigateToView(.home)
            }
        }
    }
    
    private func shouldNavigateToHome() -> Bool {
        // Add logic to determine if we should navigate to home
        // For example, if shelf is empty or certain conditions are met
        return true // Simplified for now
    }
    
    // MARK: - Screen Management
    
    private func validateSelectedScreen() {
        let availableScreens = NSScreen.screens.map { $0.localizedName }
        
        if !availableScreens.contains(selectedScreen) {
            let newScreen = NSScreen.main?.localizedName ?? "Unknown"
            Logger.log("Selected screen no longer available, switching to: \(newScreen)", category: .warning)
            selectedScreen = newScreen
        }
    }
    
    // MARK: - External Actions
    
    func toggleMic() {
        Logger.log("Toggling microphone", category: .debug)
        notifier.postNotification(name: notifier.toggleMicNotification.name, userInfo: nil)
    }
    
    func showClipboard() {
        Logger.log("Showing clipboard", category: .ui)
        notifier.postNotification(name: notifier.showClipboardNotification.name, userInfo: nil)
    }
    
    func hideClipboard() {
        Logger.log("Hiding clipboard", category: .ui)
        notifier.postNotification(name: notifier.hideClipboardNotification.name, userInfo: nil)
    }
    
    // MARK: - Analytics and Debugging
    
    func trackViewUsage() {
        // Track which views are used most frequently
        let currentTime = Date()
        // Implementation would depend on analytics framework
        Logger.log("View usage tracked: \(currentView.displayName)", category: .debug)
    }
    
    func getSystemInfo() -> [String: Any] {
        return [
            "currentView": currentView.rawValue,
            "selectedScreen": selectedScreen,
            "availableScreens": NSScreen.screens.map { $0.localizedName },
            "firstLaunch": firstLaunch,
            "hudReplacement": hudReplacement,
            "musicLiveActivity": showMusicLiveActivityOnClosed,
            "micStatus": currentMicStatus
        ]
    }
    
    // MARK: - Error Handling
    
    func handleError(_ error: Error, context: String) {
        Logger.log("Error in \(context): \(error.localizedDescription)", category: .error)
        
        // Could implement error recovery strategies here
        switch error {
        case let nsError as NSError where nsError.domain == NSCocoaErrorDomain:
            // Handle Cocoa errors
            break
        default:
            // Handle other errors
            break
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        Logger.log("BoringViewCoordinator deinitializing", category: .lifecycle)
        
        sneakPeekDispatch?.cancel()
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        
        Logger.log("BoringViewCoordinator cleanup completed", category: .lifecycle)
        Logger.trackMemory()
    }
}

// MARK: - Extensions for Convenience

extension BoringViewCoordinator {
    
    /// Check if a specific view is currently active
    func isViewActive(_ view: NotchViews) -> Bool {
        return currentView == view
    }
    
    /// Get next view in sequence
    func getNextView() -> NotchViews {
        let allViews = NotchViews.allCases
        guard let currentIndex = allViews.firstIndex(of: currentView) else { return .home }
        
        let nextIndex = (currentIndex + 1) % allViews.count
        return allViews[nextIndex]
    }
    
    /// Get previous view in sequence
    func getPreviousView() -> NotchViews {
        let allViews = NotchViews.allCases
        guard let currentIndex = allViews.firstIndex(of: currentView) else { return .home }
        
        let previousIndex = currentIndex == 0 ? allViews.count - 1 : currentIndex - 1
        return allViews[previousIndex]
    }
    
    /// Navigate to next view
    func navigateToNextView() {
        navigateToView(getNextView())
    }
    
    /// Navigate to previous view
    func navigateToPreviousView() {
        navigateToView(getPreviousView())
    }
}

// MARK: - State Persistence

extension BoringViewCoordinator {
    
    private struct CoordinatorState: Codable {
        let currentView: String
        let selectedScreen: String
        let alwaysShowTabs: Bool
        let openLastTabByDefault: Bool
        let hudReplacement: Bool
        let showMusicLiveActivityOnClosed: Bool
    }
    
    func saveState() {
        let state = CoordinatorState(
            currentView: currentView.rawValue,
            selectedScreen: selectedScreen,
            alwaysShowTabs: alwaysShowTabs,
            openLastTabByDefault: openLastTabByDefault,
            hudReplacement: hudReplacement,
            showMusicLiveActivityOnClosed: showMusicLiveActivityOnClosed
        )
        
        do {
            let data = try JSONEncoder().encode(state)
            UserDefaults.standard.set(data, forKey: "BoringViewCoordinatorState")
            Logger.log("Coordinator state saved", category: .debug)
        } catch {
            Logger.log("Failed to save coordinator state: \(error)", category: .error)
        }
    }
    
    func restoreState() {
        guard let data = UserDefaults.standard.data(forKey: "BoringViewCoordinatorState") else {
            Logger.log("No saved coordinator state found", category: .debug)
            return
        }
        
        do {
            let state = try JSONDecoder().decode(CoordinatorState.self, from: data)
            
            if let view = NotchViews(rawValue: state.currentView) {
                currentView = view
            }
            selectedScreen = state.selectedScreen
            alwaysShowTabs = state.alwaysShowTabs
            openLastTabByDefault = state.openLastTabByDefault
            hudReplacement = state.hudReplacement
            showMusicLiveActivityOnClosed = state.showMusicLiveActivityOnClosed
            
            Logger.log("Coordinator state restored", category: .success)
        } catch {
            Logger.log("Failed to restore coordinator state: \(error)", category: .error)
        }
    }
}

// MARK: - Debug Extensions

#if DEBUG
extension BoringViewCoordinator {
    
    func debugPrintState() {
        print("""
        BoringViewCoordinator Debug State:
        - Current View: \(currentView.displayName)
        - Selected Screen: \(selectedScreen)
        - First Launch: \(firstLaunch)
        - Always Show Tabs: \(alwaysShowTabs)
        - Open Last Tab: \(openLastTabByDefault)
        - HUD Replacement: \(hudReplacement)
        - Music Live Activity: \(showMusicLiveActivityOnClosed)
        - Current Mic Status: \(currentMicStatus)
        - Sneak Peek Active: \(sneakPeek.show)
        - Available Screens: \(NSScreen.screens.map { $0.localizedName })
        """)
    }
    
    func simulateSneakPeek(_ type: SneakContentType) {
        toggleSneakPeek(
            status: true,
            type: type,
            duration: 2.0,
            value: 75,
            icon: type.iconName
        )
    }
    
    func cycleThroughViews() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            self.navigateToNextView()
            
            if self.currentView == .home {
                timer.invalidate()
            }
        }
    }
}
#endif