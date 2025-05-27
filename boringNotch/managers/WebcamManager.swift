import AVFoundation
import SwiftUI

// MARK: - WebcamState

enum WebcamState: Equatable {
    case uninitialized
    case unauthorized
    case authorized
    case configuring
    case running
    case stopped
    case error(String)
    
    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
    
    var canStart: Bool {
        switch self {
        case .authorized, .stopped:
            return true
        default:
            return false
        }
    }
}

// MARK: - WebcamConfiguration

struct WebcamConfiguration {
    var sessionPreset: AVCaptureSession.Preset = .high
    var preferExternalCamera: Bool = true
    var enableLowLightBoost: Bool = true
    var maxRetryAttempts: Int = 3
    var retryDelay: TimeInterval = 1.0
}

// MARK: - WebcamManager

@MainActor
class WebcamManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            Logger.log("Preview layer updated", category: .ui)
            objectWillChange.send()
        }
    }
    
    @Published private(set) var state: WebcamState = .uninitialized {
        didSet {
            Logger.log("Webcam state changed: \(oldValue) -> \(state)", category: .lifecycle)
            objectWillChange.send()
        }
    }
    
    @Published private(set) var authorizationStatus: AVAuthorizationStatus = .notDetermined {
        didSet {
            Logger.log("Authorization status changed: \(authorizationStatus)", category: .lifecycle)
            objectWillChange.send()
        }
    }
    
    @Published private(set) var availableDevices: [AVCaptureDevice] = [] {
        didSet {
            Logger.log("Available devices updated: \(availableDevices.count) devices", category: .debug)
            objectWillChange.send()
        }
    }
    
    @Published private(set) var currentDevice: AVCaptureDevice? {
        didSet {
            if let device = currentDevice {
                Logger.log("Current device set: \(device.localizedName)", category: .debug)
            } else {
                Logger.log("Current device cleared", category: .debug)
            }
        }
    }
    
    // MARK: - Private Properties
    
    private var captureSession: AVCaptureSession?
    private var videoInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?
    
    private let sessionQueue = DispatchQueue(label: "WebcamManager.SessionQueue", qos: .userInitiated)
    private let configuration: WebcamConfiguration
    private var retryCount = 0
    private var setupTask: Task<Void, Never>?
    
    // MARK: - Observers
    
    private var deviceObserver: NSObjectProtocol?
    private var runtimeErrorObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    
    // MARK: - Initialization
    
    override init() {
        self.configuration = WebcamConfiguration()
        super.init()
        
        Logger.log("WebcamManager initializing", category: .lifecycle)
        setupInitialState()
    }
    
    init(configuration: WebcamConfiguration) {
        self.configuration = configuration
        super.init()
        
        Logger.log("WebcamManager initializing with custom configuration", category: .lifecycle)
        setupInitialState()
    }
    
    deinit {
        Logger.log("WebcamManager deinitializing", category: .lifecycle)
        cleanup()
    }
    
    // MARK: - Setup Methods
    
    private func setupInitialState() {
        checkAndRequestVideoAuthorization()
        setupNotificationObservers()
        updateAvailableDevices()
    }
    
    private func setupNotificationObservers() {
        let notificationCenter = NotificationCenter.default
        
        deviceObserver = notificationCenter.addObserver(
            forName: .AVCaptureDeviceWasConnected,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let device = notification.object as? AVCaptureDevice {
                Logger.log("Camera device connected: \(device.localizedName)", category: .lifecycle)
                self?.handleDeviceConnected(device)
            }
        }
        
        let disconnectObserver = notificationCenter.addObserver(
            forName: .AVCaptureDeviceWasDisconnected,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let device = notification.object as? AVCaptureDevice {
                Logger.log("Camera device disconnected: \(device.localizedName)", category: .lifecycle)
                self?.handleDeviceDisconnected(device)
            }
        }
        
        runtimeErrorObserver = notificationCenter.addObserver(
            forName: .AVCaptureSessionRuntimeError,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError {
                Logger.log("Runtime error: \(error.localizedDescription)", category: .error)
                self?.handleRuntimeError(error)
            }
        }
        
        interruptionObserver = notificationCenter.addObserver(
            forName: .AVCaptureSessionWasInterrupted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let reason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? AVCaptureSession.InterruptionReason {
                Logger.log("Session interrupted: \(reason)", category: .warning)
                self?.handleSessionInterruption(reason)
            }
        }
    }
    
    // MARK: - Public Methods
    
    func checkAndRequestVideoAuthorization() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        authorizationStatus = status
        
        switch status {
        case .authorized:
            state = .authorized
            updateAvailableDevices()
        case .notDetermined:
            requestVideoAccess()
        case .denied, .restricted:
            state = .unauthorized
            Logger.log("Camera access denied or restricted", category: .warning)
        @unknown default:
            state = .error("Unknown authorization status")
            Logger.log("Unknown authorization status", category: .error)
        }
    }
    
    func startSession() {
        guard state.canStart else {
            Logger.log("Cannot start session in current state: \(state)", category: .warning)
            return
        }
        
        Logger.log("Starting webcam session", category: .lifecycle)
        
        setupTask?.cancel()
        setupTask = Task {
            await performSessionSetup()
        }
    }
    
    func stopSession() {
        Logger.log("Stopping webcam session", category: .lifecycle)
        
        setupTask?.cancel()
        
        Task {
            await performSessionCleanup()
        }
    }
    
    func restartSession() {
        Logger.log("Restarting webcam session", category: .lifecycle)
        
        Task {
            await performSessionCleanup()
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
            await performSessionSetup()
        }
    }
    
    func selectDevice(_ device: AVCaptureDevice) {
        guard availableDevices.contains(device) else {
            Logger.log("Attempted to select unavailable device", category: .warning)
            return
        }
        
        Logger.log("Selecting device: \(device.localizedName)", category: .debug)
        
        Task {
            await switchToDevice(device)
        }
    }
    
    // MARK: - Private Methods
    
    private func requestVideoAccess() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            Task { @MainActor in
                self?.authorizationStatus = granted ? .authorized : .denied
                self?.state = granted ? .authorized : .unauthorized
                
                if granted {
                    self?.updateAvailableDevices()
                }
            }
        }
    }
    
    private func updateAvailableDevices() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera, .builtInUltraWideCamera],
            mediaType: .video,
            position: .unspecified
        )
        
        availableDevices = discoverySession.devices
        
        // Select preferred device
        if currentDevice == nil && !availableDevices.isEmpty {
            selectPreferredDevice()
        }
    }
    
    private func selectPreferredDevice() {
        let preferredDevice: AVCaptureDevice?
        
        if configuration.preferExternalCamera {
            preferredDevice = availableDevices.first { $0.deviceType == .external } ?? availableDevices.first
        } else {
            preferredDevice = availableDevices.first
        }
        
        if let device = preferredDevice {
            currentDevice = device
            Logger.log("Selected preferred device: \(device.localizedName)", category: .success)
        }
    }
    
    private func performSessionSetup() async {
        guard state == .authorized || state == .stopped else {
            Logger.log("Cannot setup session - invalid state: \(state)", category: .warning)
            return
        }
        
        await MainActor.run {
            state = .configuring
        }
        
        do {
            let session = try await createCaptureSession()
            
            await MainActor.run {
                self.captureSession = session
                self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
                self.previewLayer?.videoGravity = .resizeAspectFill
                
                session.startRunning()
                self.state = .running
                self.retryCount = 0
                
                Logger.log("Webcam session started successfully", category: .success)
                Logger.trackMemory()
            }
            
        } catch {
            await MainActor.run {
                self.state = .error(error.localizedDescription)
                Logger.log("Failed to setup session: \(error.localizedDescription)", category: .error)
            }
            
            // Retry logic
            if retryCount < configuration.maxRetryAttempts {
                retryCount += 1
                Logger.log("Retrying session setup (attempt \(retryCount))", category: .debug)
                
                try? await Task.sleep(nanoseconds: UInt64(configuration.retryDelay * 1_000_000_000))
                await performSessionSetup()
            }
        }
    }
    
    private func createCaptureSession() async throws -> AVCaptureSession {
        guard let device = currentDevice else {
            throw WebcamError.noDeviceAvailable
        }
        
        let session = AVCaptureSession()
        session.beginConfiguration()
        
        // Configure session preset
        if session.canSetSessionPreset(configuration.sessionPreset) {
            session.sessionPreset = configuration.sessionPreset
        }
        
        // Create and add video input
        let videoInput = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(videoInput) else {
            throw WebcamError.cannotAddInput
        }
        session.addInput(videoInput)
        self.videoInput = videoInput
        
        // Create and add video output
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        guard session.canAddOutput(videoOutput) else {
            throw WebcamError.cannotAddOutput
        }
        session.addOutput(videoOutput)
        self.videoOutput = videoOutput
        
        // Configure device settings
        try configureDevice(device)
        
        session.commitConfiguration()
        
        return session
    }
    
    private func configureDevice(_ device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        
        // Enable low light boost if available and requested
        if configuration.enableLowLightBoost && device.isLowLightBoostSupported {
            device.automaticallyEnablesLowLightBoostWhenAvailable = true
        }
        
        // Set focus mode to continuous auto focus if available
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        
        // Set exposure mode to continuous auto exposure if available
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        
        Logger.log("Device configured: \(device.localizedName)", category: .debug)
    }
    
    private func performSessionCleanup() async {
        await MainActor.run {
            state = .stopped
        }
        
        if let session = captureSession {
            if session.isRunning {
                session.stopRunning()
            }
            
            session.beginConfiguration()
            
            // Remove all inputs and outputs
            for input in session.inputs {
                session.removeInput(input)
            }
            for output in session.outputs {
                session.removeOutput(output)
            }
            
            session.commitConfiguration()
        }
        
        await MainActor.run {
            self.captureSession = nil
            self.videoInput = nil
            self.videoOutput = nil
            self.previewLayer = nil
            
            Logger.log("Webcam session cleaned up", category: .lifecycle)
            Logger.trackMemory()
        }
    }
    
    private func switchToDevice(_ device: AVCaptureDevice) async {
        guard currentDevice != device else { return }
        
        currentDevice = device
        
        if state == .running {
            await performSessionCleanup()
            await performSessionSetup()
        }
    }
    
    // MARK: - Event Handlers
    
    private func handleDeviceConnected(_ device: AVCaptureDevice) {
        updateAvailableDevices()
        
        // Auto-select external camera if preferred and none currently selected
        if configuration.preferExternalCamera && 
           device.deviceType == .external && 
           (currentDevice?.deviceType != .external || currentDevice == nil) {
            selectDevice(device)
        }
    }
    
    private func handleDeviceDisconnected(_ device: AVCaptureDevice) {
        updateAvailableDevices()
        
        // If current device was disconnected, select a new one
        if currentDevice == device {
            currentDevice = nil
            
            if state == .running {
                Task {
                    await performSessionCleanup()
                    selectPreferredDevice()
                    if currentDevice != nil {
                        await performSessionSetup()
                    }
                }
            } else {
                selectPreferredDevice()
            }
        }
    }
    
    private func handleRuntimeError(_ error: AVError) {
        state = .error(error.localizedDescription)
        
        // Attempt recovery for certain error types
        switch error.code {
        case .mediaServicesWereReset:
            Logger.log("Media services reset - attempting recovery", category: .warning)
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                await performSessionSetup()
            }
        default:
            Logger.log("Unrecoverable runtime error: \(error.localizedDescription)", category: .error)
        }
    }
    
    private func handleSessionInterruption(_ reason: AVCaptureSession.InterruptionReason) {
        switch reason {
        case .audioDeviceInUseByAnotherClient, .videoDeviceInUseByAnotherClient:
            Logger.log("Device in use by another client", category: .warning)
        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            Logger.log("Device not available with multiple foreground apps", category: .warning)
        case .videoDeviceNotAvailableDueToSystemPressure:
            Logger.log("Device not available due to system pressure", category: .warning)
        @unknown default:
            Logger.log("Unknown interruption reason", category: .warning)
        }
    }
    
    // MARK: - Cleanup
    
    private func cleanup() {
        setupTask?.cancel()
        
        // Remove observers
        if let observer = deviceObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = runtimeErrorObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        // Clean up session
        Task {
            await performSessionCleanup()
        }
        
        Logger.log("WebcamManager cleanup completed", category: .lifecycle)
        Logger.trackMemory()
    }
}

// MARK: - WebcamError

enum WebcamError: LocalizedError {
    case noDeviceAvailable
    case cannotAddInput
    case cannotAddOutput
    case deviceConfigurationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noDeviceAvailable:
            return "No camera device available"
        case .cannotAddInput:
            return "Cannot add camera input to session"
        case .cannotAddOutput:
            return "Cannot add video output to session"
        case .deviceConfigurationFailed(let message):
            return "Device configuration failed: \(message)"
        }
    }
}

// MARK: - Extensions

extension WebcamManager {
    
    var isSessionRunning: Bool {
        state.isRunning
    }
    
    var cameraAvailable: Bool {
        !availableDevices.isEmpty
    }
    
    var canAccessCamera: Bool {
        authorizationStatus == .authorized
    }
}

// MARK: - SwiftUI Integration

extension WebcamManager {
    
    func previewView() -> some View {
        Group {
            if let previewLayer = previewLayer {
                WebcamPreviewView(previewLayer: previewLayer)
            } else {
                Rectangle()
                    .fill(Color.black)
                    .overlay {
                        VStack {
                            Image(systemName: "camera.fill")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                            Text("Camera Unavailable")
                                .foregroundColor(.gray)
                        }
                    }
            }
        }
    }
}

struct WebcamPreviewView: NSViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.layer = previewLayer
        view.wantsLayer = true
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.layer = previewLayer
    }
}