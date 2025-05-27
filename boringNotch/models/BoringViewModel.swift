import Combine
import Defaults
import SwiftUI
import TheBoringWorkerNotifier

// MARK: - Supporting Types

enum BrowserType {
    case chromium
    case safari
    case webkit
    case firefox
    case unknown
}

enum NotchAnimationState {
    case idle
    case opening
    case closing
    case transitioning
}

struct ExpandedItem: Equatable {
    var show: Bool = false
    var type: SneakContentType = .battery
    var value: CGFloat = 0
    var browser: BrowserType = .chromium
    var duration: TimeInterval = 3.0
    
    static func == (lhs: ExpandedItem, rhs: ExpandedItem) -> Bool {
        lhs.show == rhs.show &&
        lhs.type == rhs.type &&
        lhs.value == rhs.value &&
        lhs.browser == rhs.browser
    }
}

struct NotchState: Equatable {
    var state: NotchStateType = .closed
    var animationState: NotchAnimationState = .idle
    var size: CGSize = getClosedNotchSize()
    var targetSize: CGSize = getClosedNotchSize()
    
    static func == (lhs: NotchState, rhs: NotchState) -> Bool {
        lhs.state == rhs.state &&
        lhs.animationState == rhs.animationState &&
        lhs.size == rhs.size
    }
}

enum NotchStateType {
    case closed
    case open
}

// MARK: - BoringViewModel

@MainActor
class BoringViewModel: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var contentType: ContentType = .normal
    @Published private(set) var notchState: NotchStateType = .closed
    @Published private(set) var animationState: NotchAnimationState = .idle
    @Published var dragDetectorTargeting: Bool = false
    @Published var dropZoneTargeting: Bool = false
    @Published var dropEvent: Bool = false
    @Published var anyDropZoneTargeting: Bool = false
    @Published var notchSize: CGSize = getClosedNotchSize()
    @Published var closedNotchSize: CGSize = getClosedNotchSize()
    @Published var expandingView: ExpandedItem = .init()
    
    // MARK: - Private Properties
    private var cancellables: Set<AnyCancellable> = []
    private var expandingViewDispatch: DispatchWorkItem?
    private var animationWorkItem: DispatchWorkItem?
    private let stateQueue = DispatchQueue(label: "com.boringnotch.state", qos: .userInteractive)
    
    // MARK: - Dependencies
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    let animationLibrary: BoringAnimations = .init()
    let animation: Animation?
    var notifier: TheBoringWorkerNotifier = .init()
    var screen: String?
    
    // MARK: - Initialization
    
    override init() {
        self.animation = animationLibrary.animation
        super.init()
        setupInitialState()
        setupObservers()
        Logger.log("BoringViewModel initialized", category: .lifecycle)
    }
    
    convenience init(screen: String?) {
        self.init()
        self.screen = screen
        updateNotchSizes()
        Logger.log("BoringViewModel initialized for screen: \(screen ?? "default")", category: .lifecycle)
    }
    
    deinit {
        Logger.log("BoringViewModel deinitializing", category: .lifecycle)
        cleanup()
    }
    
    // MARK: - Setup Methods
    
    private func setupInitialState() {
        notifier = coordinator.notifier
        updateNotchSizes()
    }
    
    private func setupObservers() {
        // Combine drop zone targeting states
        Publishers.CombineLatest($dropZoneTargeting, $dragDetectorTargeting)
            .map { $0 || $1 }
            .removeDuplicates()
            .assign(to: \.anyDropZoneTargeting, on: self)
            .store(in: &cancellables)
        
        // Monitor expanding view changes
        $expandingView
            .removeDuplicates()
            .sink { [weak self] expandingView in
                self?.handleExpandingViewChange(expandingView)
            }
            .store(in: &cancellables)
        
        // Monitor screen changes
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateNotchSizes()
            }
            .store(in: &cancellables)
    }
    
    private func updateNotchSizes() {
        let newSize = getClosedNotchSize(screen: screen)
        
        if newSize != closedNotchSize {
            Logger.log("Updating notch sizes for screen: \(screen ?? "default")", category: .ui)
            
            withAnimation(.easeInOut(duration: 0.3)) {
                closedNotchSize = newSize
                if notchState == .closed {
                    notchSize = newSize
                }
            }
        }
    }
    
    // MARK: - Public Methods
    
    func open() {
        guard notchState == .closed && animationState == .idle else {
            Logger.log("Cannot open notch - invalid state", category: .warning)
            return
        }
        
        Logger.log("Opening notch", category: .ui)
        setAnimationState(.opening)
        
        withAnimation(.bouncy) {
            self.notchSize = CGSize(width: openNotchSize.width, height: openNotchSize.height)
            self.notchState = .open
        }
        
        // Reset animation state after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.setAnimationState(.idle)
        }
    }
    
    func close() {
        guard notchState == .open && animationState == .idle else {
            Logger.log("Cannot close notch - invalid state", category: .warning)
            return
        }
        
        Logger.log("Closing notch", category: .ui)
        setAnimationState(.closing)
        
        withAnimation(.smooth) {
            self.notchSize = getClosedNotchSize(screen: screen)
            self.closedNotchSize = self.notchSize
            self.notchState = .closed
        }
        
        // Update view state based on preferences
        updateCurrentViewAfterClose()
        
        // Reset animation state after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.setAnimationState(.idle)
        }
    }
    
    func toggleMusicLiveActivity(status: Bool) {
        Logger.log("Toggling music live activity: \(status)", category: .debug)
        
        withAnimation(.smooth) {
            self.coordinator.showMusicLiveActivityOnClosed = status
        }
    }
    
    func toggleExpandingView(
        status: Bool,
        type: SneakContentType,
        value: CGFloat = 0,
        browser: BrowserType = .chromium,
        duration: TimeInterval = 3.0
    ) {
        Logger.log("Toggling expanding view: \(status) for type: \(type)", category: .debug)
        
        if expandingView.show && !status {
            withAnimation(.smooth) {
                self.expandingView.show = false
            }
        }
        
        DispatchQueue.main.async {
            withAnimation(.smooth) {
                self.expandingView = ExpandedItem(
                    show: status,
                    type: type,
                    value: value,
                    browser: browser,
                    duration: duration
                )
            }
        }
    }
    
    func isMouseHovering(position: NSPoint = NSEvent.mouseLocation) -> Bool {
        guard let screenFrame = getScreenFrame(screen) else { return false }
        
        let baseY = screenFrame.maxY - notchSize.height
        let baseX = screenFrame.midX - notchSize.width / 2
        
        let isHovering = position.y >= baseY && 
                        position.x >= baseX && 
                        position.x <= baseX + notchSize.width
        
        if isHovering {
            Logger.log("Mouse hovering over notch", category: .debug)
        }
        
        return isHovering
    }
    
    func openClipboard() {
        Logger.log("Opening clipboard", category: .ui)
        notifier.postNotification(name: notifier.showClipboardNotification.name, userInfo: nil)
    }
    
    func toggleClipboard() {
        openClipboard()
    }
    
    func closeHello() {
        Logger.log("Closing hello animation", category: .ui)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            self?.coordinator.firstLaunch = false
            withAnimation(self?.animationLibrary.animation) {
                self?.close()
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func setAnimationState(_ state: NotchAnimationState) {
        guard animationState != state else { return }
        
        animationState = state
        Logger.log("Animation state changed to: \(state)", category: .debug)
    }
    
    private func handleExpandingViewChange(_ expandingView: ExpandedItem) {
        if expandingView.show {
            expandingViewDispatch?.cancel()
            
            expandingViewDispatch = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                Logger.log("Auto-hiding expanding view after timeout", category: .debug)
                self.toggleExpandingView(status: false, type: .battery)
            }
            
            let delay = expandingView.type == .download ? 2.0 : expandingView.duration
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: expandingViewDispatch!)
        }
    }
    
    private func updateCurrentViewAfterClose() {
        if !TrayDrop.shared.isEmpty && Defaults[.openShelfByDefault] {
            coordinator.currentView = .shelf
        } else if !coordinator.openLastTabByDefault {
            coordinator.currentView = .home
        }
    }
    
    private func cleanup() {
        // Cancel all work items
        expandingViewDispatch?.cancel()
        animationWorkItem?.cancel()
        
        // Clear cancellables
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        
        Logger.log("BoringViewModel cleanup completed", category: .lifecycle)
        Logger.trackMemory()
    }
}

// MARK: - State Management Extensions

extension BoringViewModel {
    
    /// Safe state transition with validation
    func transitionToState(_ newState: NotchStateType, animated: Bool = true) {
        guard canTransitionTo(newState) else {
            Logger.log("Invalid state transition from \(notchState) to \(newState)", category: .warning)
            return
        }
        
        switch newState {
        case .open:
            open()
        case .closed:
            close()
        }
    }
    
    /// Check if transition to new state is valid
    private func canTransitionTo(_ newState: NotchStateType) -> Bool {
        switch (notchState, newState, animationState) {
        case (.closed, .open, .idle):
            return true
        case (.open, .closed, .idle):
            return true
        case (let current, let new, _) where current == new:
            return false // No need to transition to same state
        default:
            return false // Invalid transition
        }
    }
    
    /// Force reset to a specific state (use with caution)
    func forceResetToState(_ state: NotchStateType) {
        Logger.log("Force resetting to state: \(state)", category: .warning)
        
        cancellables.forEach { $0.cancel() }
        expandingViewDispatch?.cancel()
        animationWorkItem?.cancel()
        
        notchState = state
        animationState = .idle
        
        switch state {
        case .closed:
            notchSize = closedNotchSize
        case .open:
            notchSize = openNotchSize
        }
        
        setupObservers()
    }
}

// MARK: - Debug Extensions

#if DEBUG
extension BoringViewModel {
    
    func debugPrintState() {
        print("""
        BoringViewModel Debug State:
        - notchState: \(notchState)
        - animationState: \(animationState)
        - notchSize: \(notchSize)
        - closedNotchSize: \(closedNotchSize)
        - expandingView: \(expandingView)
        - screen: \(screen ?? "default")
        """)
    }
    
    func simulateStateChange() {
        switch notchState {
        case .closed:
            open()
        case .open:
            close()
        }
    }
}
#endif

// MARK: - Helper Functions

func getScreenFrame(_ screen: String? = nil) -> CGRect? {
    var selectedScreen = NSScreen.main
    
    if let customScreen = screen {
        selectedScreen = NSScreen.screens.first { $0.localizedName == customScreen }
    }
    
    return selectedScreen?.frame
}

// MARK: - TrayDrop Placeholder (if not defined elsewhere)
struct TrayDrop {
    static let shared = TrayDrop()
    var isEmpty: Bool { true } // Replace with actual implementation
}