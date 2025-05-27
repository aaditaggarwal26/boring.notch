import AVFoundation
import Combine
import KeyboardShortcuts
import Sparkle
import SwiftUI
import Defaults

// MARK: - Main App

@main
struct DynamicNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Default(.menubarIcon) var showMenuBarIcon
    @Environment(\.openWindow) var openWindow
    
    let updaterController: SPUStandardUpdaterController
    
    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        
        Logger.log("DynamicNotchApp initializing", category: .lifecycle)
    }
    
    var body: some Scene {
        MenuBarExtra("boring.notch", systemImage: "sparkle", isInserted: $showMenuBarIcon) {
            MenuBarContentView(updaterController: updaterController, openWindow: openWindow)
        }
        
        Settings {
            SettingsView(updaterController: updaterController)
        }
        
        Window("Onboarding", id: "onboarding") {
            ProOnboard()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        
        Window("Activation", id: "activation") {
            ActivationWindow()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

// MARK: - MenuBar Content

struct MenuBarContentView: View {
    let updaterController: SPUStandardUpdaterController
    let openWindow: OpenWindowAction
    
    var body: some View {
        SettingsLink(label: {
            Text("Settings")
        })
        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
        
        if false { // License activation disabled for now
            Button("Activate License") {
                openWindow(id: "activation")
            }
        }
        
        CheckForUpdatesView(updater: updaterController.updater)
        
        Divider()
        
        Button("Restart Boring Notch") {
            AppLifecycleManager.shared.restartApp()
        }
        
        Button("Quit", role: .destructive) {
            NSApp.terminate(nil)
        }
        .keyboardShortcut(KeyEquivalent("Q"), modifiers: .command)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Properties
    
    private let windowManager = NotchWindowManager()
    private let lifecycleManager = AppLifecycleManager.shared
    private let keyboardShortcutManager = KeyboardShortcutManager()
    private let systemEventManager = SystemEventManager()
    
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    
    // MARK: - Application Lifecycle
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        Logger.log("Application terminating", category: .lifecycle)
        cleanup()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.log("Application launched", category: .lifecycle)
        Logger.trackMemory()
        
        setupApplication()
        
        if coordinator.firstLaunch {
            handleFirstLaunch()
        }
    }
    
    // MARK: - Setup Methods
    
    private func setupApplication() {
        coordinator.setupWorkersNotificationObservers()
        systemEventManager.setup()
        keyboardShortcutManager.setup(windowManager: windowManager)
        windowManager.setup()
        
        Logger.log("Application setup completed", category: .success)
    }
    
    private func handleFirstLaunch() {
        DispatchQueue.main.async { [weak self] in
            self?.coordinator.openWindow(id: "onboarding")
        }
        
        AudioManager.shared.playWelcomeSound()
        Logger.log("First launch handled", category: .lifecycle)
    }
    
    private func cleanup() {
        windowManager.cleanup()
        systemEventManager.cleanup()
        keyboardShortcutManager.cleanup()
        
        NotificationCenter.default.removeObserver(self)
        
        Logger.log("App delegate cleanup completed", category: .lifecycle)
        Logger.trackMemory()
    }
}

// MARK: - Window Management

@MainActor
class NotchWindowManager: ObservableObject {
    
    // MARK: - Properties
    
    @Published private(set) var windows: [NSScreen: NSWindow] = [:]
    @Published private(set) var viewModels: [NSScreen: BoringViewModel] = [:]
    @Published private(set) var primaryWindow: NSWindow?
    
    private let vm: BoringViewModel = .init()
    private var previousScreens: [NSScreen] = []
    private var cleanupWorkItem: DispatchWorkItem?
    
    // MARK: - Setup
    
    func setup() {
        Logger.log("Setting up window manager", category: .lifecycle)
        
        setupNotificationObservers()
        adjustWindowPosition()
        
        Logger.log("Window manager setup completed", category: .success)
    }
    
    private func setupNotificationObservers() {
        let notificationCenter = NotificationCenter.default
        
        notificationCenter.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        
        notificationCenter.addObserver(
            forName: Notification.Name.selectedScreenChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.adjustWindowPosition(changeAlpha: true)
        }
        
        notificationCenter.addObserver(
            forName: Notification.Name.notchHeightChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.adjustWindowPosition()
        }
        
        notificationCenter.addObserver(
            forName: Notification.Name.showOnAllDisplaysChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDisplayModeChange()
        }
    }
    
    // MARK: - Window Creation and Management
    
    private func createNotchWindow() -> NSWindow {
        let window = BoringNotchWindow(
            contentRect: NSRect(x: 0, y: 0, width: openNotchSize.width, height: openNotchSize.height),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        
        return window
    }
    
    private func setupWindowContent(window: NSWindow, viewModel: BoringViewModel) {
        let contentView = ContentView(batteryModel: .init(vm: viewModel))
            .environmentObject(viewModel)
            .environmentObject(MusicManager(vm: viewModel) ?? MusicManager(vm: BoringViewModel())!)
        
        window.contentView = NSHostingView(rootView: contentView)
    }
    
    @objc private func adjustWindowPosition(changeAlpha: Bool = false) {
        Logger.log("Adjusting window positions", category: .ui)
        
        if Defaults[.showOnAllDisplays] {
            adjustMultiDisplayWindows(changeAlpha: changeAlpha)
        } else {
            adjustSingleDisplayWindow(changeAlpha: changeAlpha)
        }
    }
    
    private func adjustMultiDisplayWindows(changeAlpha: Bool) {
        for screen in NSScreen.screens {
            if windows[screen] == nil {
                createWindowForScreen(screen)
            }
            
            if let window = windows[screen] {
                positionWindow(window, on: screen, changeAlpha: changeAlpha)
            }
            
            // Ensure closed state for new screens
            if let viewModel = viewModels[screen], viewModel.notchState == .closed {
                viewModel.close()
            }
        }
        
        // Remove windows for disconnected screens
        let currentScreens = Set(NSScreen.screens)
        let windowScreens = Set(windows.keys)
        let screensToRemove = windowScreens.subtracting(currentScreens)
        
        for screen in screensToRemove {
            removeWindowForScreen(screen)
        }
    }
    
    private func adjustSingleDisplayWindow(changeAlpha: Bool) {
        let coordinator = BoringViewCoordinator.shared
        
        // Validate selected screen
        if !NSScreen.screens.contains(where: { $0.localizedName == coordinator.preferredScreen }) {
            coordinator.selectedScreen = NSScreen.main?.localizedName ?? "Unknown"
        }
        
        guard let selectedScreen = NSScreen.screens.first(where: { $0.localizedName == coordinator.selectedScreen }) else {
            Logger.log("Selected screen not found", category: .error)
            return
        }
        
        // Update notch size for current screen
        vm.notchSize = getClosedNotchSize(screen: selectedScreen.localizedName)
        
        // Create window if needed
        if primaryWindow == nil {
            primaryWindow = createNotchWindow()
            setupWindowContent(window: primaryWindow!, viewModel: vm)
            NotchSpaceManager.shared.notchSpace.windows.insert(primaryWindow!)
        }
        
        // Position window
        if let window = primaryWindow {
            positionWindow(window, on: selectedScreen, changeAlpha: changeAlpha)
        }
        
        // Ensure closed state
        if vm.notchState == .closed {
            vm.close()
        }
    }
    
    private func createWindowForScreen(_ screen: NSScreen) {
        let viewModel = BoringViewModel(screen: screen.localizedName)
        let window = createNotchWindow()
        
        setupWindowContent(window: window, viewModel: viewModel)
        
        windows[screen] = window
        viewModels[screen] = viewModel
        
        window.orderFrontRegardless()
        NotchSpaceManager.shared.notchSpace.windows.insert(window)
        
        Logger.log("Created window for screen: \(screen.localizedName)", category: .success)
    }
    
    private func removeWindowForScreen(_ screen: NSScreen) {
        if let window = windows[screen] {
            window.close()
            NotchSpaceManager.shared.notchSpace.windows.remove(window)
            windows.removeValue(forKey: screen)
            viewModels.removeValue(forKey: screen)
            
            Logger.log("Removed window for screen: \(screen.localizedName)", category: .lifecycle)
        }
    }
    
    private func positionWindow(_ window: NSWindow, on screen: NSScreen, changeAlpha: Bool) {
        if changeAlpha {
            window.alphaValue = 0
        }
        
        window.makeKeyAndOrderFront(nil)
        
        DispatchQueue.main.async {
            let origin = NSPoint(
                x: screen.frame.origin.x + (screen.frame.width / 2) - window.frame.width / 2,
                y: screen.frame.origin.y + screen.frame.height - window.frame.height
            )
            
            window.setFrameOrigin(origin)
            
            if changeAlpha {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    window.animator().alphaValue = 1
                }
            } else {
                window.alphaValue = 1
            }
        }
    }
    
    // MARK: - Event Handlers
    
    @objc private func screenConfigurationDidChange() {
        let currentScreens = NSScreen.screens
        let screensChanged = currentScreens.count != previousScreens.count ||
            Set(currentScreens.map { $0.localizedName }) != Set(previousScreens.map { $0.localizedName })
        
        if screensChanged {
            Logger.log("Screen configuration changed", category: .lifecycle)
            previousScreens = currentScreens
            
            cleanupWorkItem?.cancel()
            cleanupWorkItem = DispatchWorkItem { [weak self] in
                self?.cleanupWindows()
                self?.adjustWindowPosition()
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: cleanupWorkItem!)
        }
    }
    
    private func handleDisplayModeChange() {
        Logger.log("Display mode changed", category: .lifecycle)
        
        cleanupWindows()
        
        if Defaults[.showOnAllDisplays] {
            primaryWindow?.close()
            primaryWindow = nil
        } else {
            // Create single window
            primaryWindow = createNotchWindow()
            setupWindowContent(window: primaryWindow!, viewModel: vm)
            NotchSpaceManager.shared.notchSpace.windows.insert(primaryWindow!)
        }
        
        adjustWindowPosition(changeAlpha: true)
    }
    
    // MARK: - Cleanup
    
    private func cleanupWindows() {
        Logger.log("Cleaning up windows", category: .lifecycle)
        
        if Defaults[.showOnAllDisplays] {
            for window in windows.values {
                window.close()
                NotchSpaceManager.shared.notchSpace.windows.remove(window)
            }
            windows.removeAll()
            viewModels.removeAll()
        } else if let window = primaryWindow {
            window.close()
            NotchSpaceManager.shared.notchSpace.windows.remove(window)
            primaryWindow = nil
        }
    }
    
    func cleanup() {
        cleanupWorkItem?.cancel()
        cleanupWindows()
        NotificationCenter.default.removeObserver(self)
        
        Logger.log("Window manager cleanup completed", category: .lifecycle)
    }
}

// MARK: - System Event Management

class SystemEventManager: NSObject {
    
    private var screenLockObserver: NSObjectProtocol?
    private var screenUnlockObserver: NSObjectProtocol?
    
    func setup() {
        Logger.log("Setting up system event monitoring", category: .lifecycle)
        
        let distributedCenter = DistributedNotificationCenter.default()
        
        screenLockObserver = distributedCenter.addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenLocked()
        }
        
        screenUnlockObserver = distributedCenter.addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenUnlocked()
        }
        
        Logger.log("System event monitoring setup completed", category: .success)
    }
    
    private func handleScreenLocked() {
        Logger.log("Screen locked", category: .lifecycle)
        // Optionally pause certain operations when screen is locked
    }
    
    private func handleScreenUnlocked() {
        Logger.log("Screen unlocked", category: .lifecycle)
        
        // Reset and readjust windows when screen unlocks
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            NotificationCenter.default.post(
                name: NSApplication.didChangeScreenParametersNotification,
                object: nil
            )
        }
    }
    
    func cleanup() {
        if let observer = screenLockObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        if let observer = screenUnlockObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        
        Logger.log("System event manager cleanup completed", category: .lifecycle)
    }
}

// MARK: - Keyboard Shortcut Management

class KeyboardShortcutManager {
    
    private weak var windowManager: NotchWindowManager?
    private var closeNotchWorkItem: DispatchWorkItem?
    
    func setup(windowManager: NotchWindowManager) {
        self.windowManager = windowManager
        
        Logger.log("Setting up keyboard shortcuts", category: .lifecycle)
        
        setupSneakPeekShortcut()
        setupToggleNotchShortcut()
        
        Logger.log("Keyboard shortcuts setup completed", category: .success)
    }
    
    private func setupSneakPeekShortcut() {
        KeyboardShortcuts.onKeyDown(for: .toggleSneakPeek) {
            Logger.log("Sneak peek shortcut triggered", category: .debug)
            
            let coordinator = BoringViewCoordinator.shared
            coordinator.toggleSneakPeek(
                status: !coordinator.sneakPeek.show,
                type: .music,
                duration: 3.0
            )
        }
    }
    
    private func setupToggleNotchShortcut() {
        KeyboardShortcuts.onKeyDown(for: .toggleNotchOpen) { [weak self] in
            Logger.log("Toggle notch shortcut triggered", category: .debug)
            self?.handleToggleNotch()
        }
    }
    
    private func handleToggleNotch() {
        let mouseLocation = NSEvent.mouseLocation
        var viewModel: BoringViewModel?
        
        // Find the appropriate view model based on mouse location
        if Defaults[.showOnAllDisplays], let windowManager = windowManager {
            for screen in NSScreen.screens {
                if screen.frame.contains(mouseLocation) {
                    viewModel = windowManager.viewModels[screen]
                    break
                }
            }
        } else {
            viewModel = windowManager?.vm
        }
        
        guard let vm = viewModel else {
            Logger.log("No view model found for toggle", category: .warning)
            return
        }
        
        switch vm.notchState {
        case .closed:
            vm.open()
            
            closeNotchWorkItem?.cancel()
            closeNotchWorkItem = DispatchWorkItem {
                vm.close()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: closeNotchWorkItem!)
            
        case .open:
            closeNotchWorkItem?.cancel()
            closeNotchWorkItem = nil
            vm.close()
        }
    }
    
    func cleanup() {
        closeNotchWorkItem?.cancel()
        Logger.log("Keyboard shortcut manager cleanup completed", category: .lifecycle)
    }
}

// MARK: - App Lifecycle Management

class AppLifecycleManager {
    
    static let shared = AppLifecycleManager()
    
    private init() {}
    
    func restartApp() {
        Logger.log("Restarting application", category: .lifecycle)
        
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            Logger.log("Failed to get bundle identifier for restart", category: .error)
            return
        }
        
        let workspace = NSWorkspace.shared
        
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            
            workspace.openApplication(at: appURL, configuration: configuration) { _, error in
                if let error = error {
                    Logger.log("Failed to restart app: \(error.localizedDescription)", category: .error)
                } else {
                    Logger.log("App restart initiated", category: .success)
                    NSApplication.shared.terminate(nil)
                }
            }
        } else {
            Logger.log("Failed to find app URL for restart", category: .error)
        }
    }
}

// MARK: - Audio Management

class AudioManager {
    
    static let shared = AudioManager()
    
    private init() {}
    
    func playWelcomeSound() {
        guard let soundURL = Bundle.main.url(forResource: "boring", withExtension: "m4a") else {
            Logger.log("Welcome sound file not found", category: .warning)
            return
        }
        
        let sound = NSSound(contentsOf: soundURL, byReference: false)
        sound?.play()
        
        Logger.log("Welcome sound played", category: .debug)
    }
}

// MARK: - Custom Window Class

class BoringNotchWindow: NSPanel {
    
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        
        // Configure window properties
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        
        // Ensure window appears in all spaces
        collectionBehavior = [.canJoinAllSpaces, .stationary]
    }
    
    override var canBecomeKey: Bool {
        return false
    }
    
    override var canBecomeMain: Bool {
        return false
    }
}

// MARK: - Extensions

extension Notification.Name {
    static let selectedScreenChanged = Notification.Name("SelectedScreenChanged")
    static let notchHeightChanged = Notification.Name("NotchHeightChanged")
    static let showOnAllDisplaysChanged = Notification.Name("showOnAllDisplaysChanged")
}

extension BoringViewCoordinator {
    func openWindow(id: String) {
        // This would be implemented to open specific windows
        // For now, it's a placeholder
        Logger.log("Opening window: \(id)", category: .ui)
    }
}