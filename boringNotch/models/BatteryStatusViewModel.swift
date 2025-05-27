import Cocoa
import SwiftUI
import IOKit.ps
import Defaults
import Combine

// MARK: - Battery State Models

struct BatteryInfo: Equatable {
    let percentage: Float
    let isPluggedIn: Bool
    let isCharging: Bool
    let isInLowPowerMode: Bool
    let timeRemaining: TimeInterval?
    let chargingState: ChargingState
    let health: BatteryHealth
    let temperature: Double?
    let cycleCount: Int?
    
    static let unknown = BatteryInfo(
        percentage: 0,
        isPluggedIn: false,
        isCharging: false,
        isInLowPowerMode: false,
        timeRemaining: nil,
        chargingState: .unknown,
        health: .unknown,
        temperature: nil,
        cycleCount: nil
    )
}

enum ChargingState: String, CaseIterable {
    case charging = "Charging"
    case pluggedIn = "Plugged In"
    case discharging = "Discharging"
    case fullyCharged = "Fully Charged"
    case unknown = "Unknown"
    
    var displayText: String {
        return rawValue
    }
}

enum BatteryHealth: String, CaseIterable {
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"
    case checkBattery = "Check Battery"
    case unknown = "Unknown"
    
    var color: Color {
        switch self {
        case .good:
            return .green
        case .fair:
            return .yellow
        case .poor, .checkBattery:
            return .red
        case .unknown:
            return .gray
        }
    }
}

// MARK: - BatteryStatusViewModel

@MainActor
class BatteryStatusViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var batteryPercentage: Float = 0.0 {
        didSet {
            if abs(batteryPercentage - oldValue) > 0.5 { // Only log significant changes
                Logger.log("Battery percentage: \(batteryPercentage)%", category: .debug)
            }
        }
    }
    
    @Published var isPluggedIn: Bool = false {
        didSet {
            if isPluggedIn != oldValue {
                Logger.log("Power adapter: \(isPluggedIn ? "connected" : "disconnected")", category: .lifecycle)
            }
        }
    }
    
    @Published var showChargingInfo: Bool = false
    @Published var isInLowPowerMode: Bool = false
    @Published var isInitialPlugIn: Bool = true
    @Published var currentBatteryInfo: BatteryInfo = .unknown
    @Published var batteryHealth: BatteryHealth = .unknown
    @Published var timeRemaining: TimeInterval? = nil
    @Published var temperature: Double? = nil
    @Published var cycleCount: Int? = nil
    
    // MARK: - Private Properties
    
    private weak var vm: BoringViewModel?
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    
    private var wasCharging: Bool = false
    private var lastUpdateTime: Date = Date()
    private var cancellables = Set<AnyCancellable>()
    
    // IOKit monitoring
    private var powerSourceChangedCallback: IOPowerSourceCallbackType?
    private var runLoopSource: Unmanaged<CFRunLoopSource>?
    private let monitoringQueue = DispatchQueue(label: "BatteryMonitoring", qos: .background)
    
    let animations: BoringAnimations = BoringAnimations()
    
    // MARK: - Initialization
    
    init(vm: BoringViewModel) {
        self.vm = vm
        
        Logger.log("BatteryStatusViewModel initializing", category: .lifecycle)
        
        setupInitialState()
        startMonitoring()
        setupPowerModeObserver()
        
        Logger.log("BatteryStatusViewModel initialized", category: .lifecycle)
    }
    
    deinit {
        Logger.log("BatteryStatusViewModel deinitializing", category: .lifecycle)
        cleanup()
    }
    
    // MARK: - Setup Methods
    
    private func setupInitialState() {
        updateBatteryStatus()
        isInLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    }
    
    private func setupPowerModeObserver() {
        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.powerStateChanged()
            }
            .store(in: &cancellables)
    }
    
    private func startMonitoring() {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        powerSourceChangedCallback = { context in
            guard let context = context else { return }
            
            let mySelf = Unmanaged<BatteryStatusViewModel>.fromOpaque(context).takeUnretainedValue()
            
            // Throttle updates to avoid excessive notifications
            DispatchQueue.main.async {
                let now = Date()
                if now.timeIntervalSince(mySelf.lastUpdateTime) > 0.5 { // Minimum 0.5s between updates
                    mySelf.lastUpdateTime = now
                    mySelf.updateBatteryStatus()
                }
            }
        }
        
        if let runLoopSource = IOPSNotificationCreateRunLoopSource(powerSourceChangedCallback!, context)?.takeRetainedValue() {
            self.runLoopSource = Unmanaged<CFRunLoopSource>.passRetained(runLoopSource)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
            Logger.log("Battery monitoring started", category: .success)
        } else {
            Logger.log("Failed to create battery monitoring run loop source", category: .error)
        }
    }
    
    // MARK: - Battery Status Updates
    
    private func updateBatteryStatus() {
        guard Defaults[.chargingInfoAllowed] else {
            Logger.log("Battery monitoring disabled in settings", category: .debug)
            return
        }
        
        monitoringQueue.async { [weak self] in
            guard let self = self else { return }
            
            let batteryInfo = self.getBatteryInfo()
            
            DispatchQueue.main.async {
                self.processBatteryUpdate(batteryInfo)
            }
        }
    }
    
    private func getBatteryInfo() -> BatteryInfo {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            Logger.log("Failed to get power source info", category: .error)
            return .unknown
        }
        
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: AnyObject] else {
                continue
            }
            
            // Only process internal battery
            if let transportType = info["Transport Type"] as? String, transportType == "Internal" {
                return parseBatteryInfo(from: info)
            }
        }
        
        return .unknown
    }
    
    private func parseBatteryInfo(from info: [String: AnyObject]) -> BatteryInfo {
        let currentCapacity = info[kIOPSCurrentCapacityKey] as? Int ?? 0
        let maxCapacity = info[kIOPSMaxCapacityKey] as? Int ?? 100
        let isCharging = info["Is Charging"] as? Bool ?? false
        let powerSource = info[kIOPSPowerSourceStateKey] as? String ?? ""
        let timeToEmpty = info[kIOPSTimeToEmptyKey] as? Int
        let timeToFull = info[kIOPSTimeToFullChargeKey] as? Int
        let temperature = info["Temperature"] as? Double
        let cycleCount = info["CycleCount"] as? Int
        let batteryHealth = info["BatteryHealth"] as? String
        
        let percentage = Float((currentCapacity * 100) / maxCapacity)
        let isACPower = powerSource == "AC Power"
        
        // Determine charging state
        let chargingState: ChargingState
        if isACPower {
            if isCharging {
                chargingState = percentage >= 100 ? .fullyCharged : .charging
            } else {
                chargingState = .pluggedIn
            }
        } else {
            chargingState = .discharging
        }
        
        // Determine time remaining
        let timeRemaining: TimeInterval?
        if isCharging, let timeToFull = timeToFull, timeToFull != kIOPSTimeRemainingUnlimited {
            timeRemaining = TimeInterval(timeToFull * 60) // Convert minutes to seconds
        } else if !isCharging, let timeToEmpty = timeToEmpty, timeToEmpty != kIOPSTimeRemainingUnlimited {
            timeRemaining = TimeInterval(timeToEmpty * 60)
        } else {
            timeRemaining = nil
        }
        
        // Parse battery health
        let health: BatteryHealth
        if let batteryHealth = batteryHealth {
            health = BatteryHealth(rawValue: batteryHealth) ?? .unknown
        } else {
            // Estimate health based on capacity if not provided
            if percentage > 80 {
                health = .good
            } else if percentage > 60 {
                health = .fair
            } else {
                health = .poor
            }
        }
        
        return BatteryInfo(
            percentage: percentage,
            isPluggedIn: isACPower,
            isCharging: isCharging,
            isInLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            timeRemaining: timeRemaining,
            chargingState: chargingState,
            health: health,
            temperature: temperature,
            cycleCount: cycleCount
        )
    }
    
    private func processBatteryUpdate(_ newInfo: BatteryInfo) {
        let oldInfo = currentBatteryInfo
        currentBatteryInfo = newInfo
        
        // Update individual properties with animation
        withAnimation(.easeInOut(duration: 0.3)) {
            batteryPercentage = newInfo.percentage
            isInLowPowerMode = newInfo.isInLowPowerMode
            batteryHealth = newInfo.health
            timeRemaining = newInfo.timeRemaining
            temperature = newInfo.temperature
            cycleCount = newInfo.cycleCount
        }
        
        // Handle power adapter connection/disconnection
        handlePowerAdapterChange(oldInfo: oldInfo, newInfo: newInfo)
        
        // Handle charging state changes
        handleChargingStateChange(oldInfo: oldInfo, newInfo: newInfo)
        
        wasCharging = newInfo.isCharging
    }
    
    private func handlePowerAdapterChange(oldInfo: BatteryInfo, newInfo: BatteryInfo) {
        // Power adapter connected
        if newInfo.isPluggedIn && !oldInfo.isPluggedIn {
            let delay = coordinator.firstLaunch ? 6.0 : 0.0
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.showPowerAdapterConnectedNotification()
            }
        }
        
        // Update plug status with animation
        withAnimation(.easeInOut(duration: 0.3)) {
            isPluggedIn = newInfo.isPluggedIn
        }
    }
    
    private func handleChargingStateChange(oldInfo: BatteryInfo, newInfo: BatteryInfo) {
        // Charging started
        if newInfo.isCharging && !wasCharging && newInfo.isPluggedIn {
            showChargingStartedNotification()
        }
        
        // Fully charged
        if newInfo.chargingState == .fullyCharged && oldInfo.chargingState != .fullyCharged {
            showFullyChargedNotification()
        }
        
        // Low battery warning
        if newInfo.percentage <= 20 && !newInfo.isPluggedIn && oldInfo.percentage > 20 {
            showLowBatteryWarning()
        }
    }
    
    // MARK: - Notification Methods
    
    private func showPowerAdapterConnectedNotification() {
        vm?.toggleExpandingView(
            status: true,
            type: .battery,
            duration: 3.0
        )
        showChargingInfo = true
        isInitialPlugIn = true
        
        Logger.log("Power adapter connected notification shown", category: .ui)
    }
    
    private func showChargingStartedNotification() {
        vm?.toggleExpandingView(
            status: true,
            type: .battery,
            duration: 2.5
        )
        showChargingInfo = true
        isInitialPlugIn = false
        
        Logger.log("Charging started notification shown", category: .ui)
    }
    
    private func showFullyChargedNotification() {
        // Optional: Show fully charged notification
        Logger.log("Battery fully charged", category: .success)
    }
    
    private func showLowBatteryWarning() {
        vm?.toggleExpandingView(
            status: true,
            type: .battery,
            value: CGFloat(batteryPercentage),
            duration: 4.0
        )
        
        Logger.log("Low battery warning shown", category: .warning)
    }
    
    // MARK: - Power Mode Observer
    
    @objc private func powerStateChanged() {
        let newLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        
        if newLowPowerMode != isInLowPowerMode {
            Logger.log("Low power mode: \(newLowPowerMode ? "enabled" : "disabled")", category: .lifecycle)
            
            withAnimation(.easeInOut(duration: 0.3)) {
                isInLowPowerMode = newLowPowerMode
            }
        }
    }
    
    // MARK: - Public Utility Methods
    
    func getTimeRemainingString() -> String? {
        guard let timeRemaining = timeRemaining else { return nil }
        
        let hours = Int(timeRemaining) / 3600
        let minutes = (Int(timeRemaining) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    func getBatteryHealthDescription() -> String {
        switch batteryHealth {
        case .good:
            return "Your battery is functioning normally."
        case .fair:
            return "Your battery is functioning normally but holds less charge than when it was new."
        case .poor:
            return "Your battery's ability to hold charge is compromised. You may experience unexpected shutdowns."
        case .checkBattery:
            return "Your battery needs service. Contact Apple or an authorized service provider."
        case .unknown:
            return "Battery health information is not available."
        }
    }
    
    func shouldShowBatteryWarning() -> Bool {
        return batteryHealth == .poor || batteryHealth == .checkBattery || batteryPercentage < 10
    }
    
    // MARK: - Cleanup
    
    private func cleanup() {
        // Cancel all subscribers
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        
        // Remove power source monitoring
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource.takeUnretainedValue(), .defaultMode)
            runLoopSource.release()
        }
        
        Logger.log("BatteryStatusViewModel cleanup completed", category: .lifecycle)
        Logger.trackMemory()
    }
}

// MARK: - Debug Extensions

#if DEBUG
extension BatteryStatusViewModel {
    
    func simulateBatteryChange(percentage: Float) {
        Logger.log("Simulating battery change: \(percentage)%", category: .debug)
        
        withAnimation(.easeInOut(duration: 0.3)) {
            batteryPercentage = percentage
        }
    }
    
    func simulatePowerAdapterConnection() {
        Logger.log("Simulating power adapter connection", category: .debug)
        showPowerAdapterConnectedNotification()
    }
    
    func simulateChargingStart() {
        Logger.log("Simulating charging start", category: .debug)
        showChargingStartedNotification()
    }
    
    func debugPrintBatteryInfo() {
        print("""
        Battery Debug Info:
        - Percentage: \(batteryPercentage)%
        - Plugged In: \(isPluggedIn)
        - Charging State: \(currentBatteryInfo.chargingState.rawValue)
        - Health: \(batteryHealth.rawValue)
        - Low Power Mode: \(isInLowPowerMode)
        - Time Remaining: \(getTimeRemainingString() ?? "Unknown")
        - Temperature: \(temperature ?? 0)°C
        - Cycle Count: \(cycleCount ?? 0)
        """)
    }
}
#endif

// MARK: - SwiftUI Helpers

extension BatteryStatusViewModel {
    
    var batteryColor: Color {
        if isInLowPowerMode {
            return .yellow
        } else if batteryPercentage <= 20 {
            return .red
        } else if batteryPercentage <= 50 {
            return .orange
        } else {
            return .green
        }
    }
    
    var batteryIcon: String {
        let percentage = Int(batteryPercentage)
        
        if isPluggedIn {
            if currentBatteryInfo.chargingState == .fullyCharged {
                return "battery.100.bolt"
            } else {
                return "battery.\(percentage).bolt"
            }
        } else {
            return "battery.\(percentage)"
        }
    }
}