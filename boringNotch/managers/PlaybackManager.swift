import SwiftUI
import AppKit
import Combine
import AVFoundation

// MARK: - Media Remote Commands

enum MediaRemoteCommand: Int, CaseIterable {
    case play = 0
    case pause = 2
    case stop = 1
    case nextTrack = 4
    case previousTrack = 5
    case togglePlayPause = 6
    case seekForward = 17
    case seekBackward = 18
    case changeVolume = 10
    case changePlaybackRate = 22
    
    var displayName: String {
        switch self {
        case .play:
            return "Play"
        case .pause:
            return "Pause"
        case .stop:
            return "Stop"
        case .nextTrack:
            return "Next Track"
        case .previousTrack:
            return "Previous Track"
        case .togglePlayPause:
            return "Toggle Play/Pause"
        case .seekForward:
            return "Seek Forward"
        case .seekBackward:
            return "Seek Backward"
        case .changeVolume:
            return "Change Volume"
        case .changePlaybackRate:
            return "Change Playback Rate"
        }
    }
}

// MARK: - Playback State

enum PlaybackState: String, CaseIterable {
    case unknown = "unknown"
    case stopped = "stopped"
    case playing = "playing"
    case paused = "paused"
    case buffering = "buffering"
    case interrupted = "interrupted"
    
    var displayName: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .stopped:
            return "Stopped"
        case .playing:
            return "Playing"
        case .paused:
            return "Paused"
        case .buffering:
            return "Buffering"
        case .interrupted:
            return "Interrupted"
        }
    }
    
    var isActive: Bool {
        self == .playing || self == .buffering
    }
}

// MARK: - Playback Error

enum PlaybackError: LocalizedError {
    case mediaRemoteFrameworkNotLoaded
    case commandNotSupported(MediaRemoteCommand)
    case executionFailed(MediaRemoteCommand, String)
    case invalidSeekTime(TimeInterval)
    case invalidVolume(Double)
    
    var errorDescription: String? {
        switch self {
        case .mediaRemoteFrameworkNotLoaded:
            return "Media Remote framework could not be loaded"
        case .commandNotSupported(let command):
            return "Command '\(command.displayName)' is not supported"
        case .executionFailed(let command, let message):
            return "Failed to execute '\(command.displayName)': \(message)"
        case .invalidSeekTime(let time):
            return "Invalid seek time: \(time)"
        case .invalidVolume(let volume):
            return "Invalid volume level: \(volume)"
        }
    }
}

// MARK: - PlaybackManager

@MainActor
class PlaybackManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var isPlaying = false {
        didSet {
            if isPlaying != oldValue {
                Logger.log("Playback state changed: \(isPlaying ? "playing" : "not playing")", category: .debug)
            }
        }
    }
    
    @Published private(set) var playbackState: PlaybackState = .unknown {
        didSet {
            if playbackState != oldValue {
                Logger.log("Playback state changed: \(oldValue.rawValue) -> \(playbackState.rawValue)", category: .debug)
                isPlaying = playbackState.isActive
            }
        }
    }
    
    @Published private(set) var volume: Double = 0.5
    @Published private(set) var playbackRate: Double = 1.0
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var lastError: PlaybackError?
    
    // MARK: - Private Properties
    
    private let mediaRemoteManager: MediaRemoteManager
    private var cancellables = Set<AnyCancellable>()
    private var stateUpdateTimer: Timer?
    private let commandQueue = DispatchQueue(label: "PlaybackManager.Commands", qos: .userInitiated)
    
    // Command execution tracking
    private var pendingCommands: Set<MediaRemoteCommand> = []
    private var commandExecutionCount: [MediaRemoteCommand: Int] = [:]
    private let maxRetryAttempts = 3
    
    // MARK: - Initialization
    
    init() {
        guard let mediaRemoteManager = MediaRemoteManager() else {
            self.mediaRemoteManager = MediaRemoteManager()! // This will be nil, but we handle it
            Logger.log("Failed to initialize MediaRemote framework", category: .error)
            lastError = .mediaRemoteFrameworkNotLoaded
            return
        }
        
        self.mediaRemoteManager = mediaRemoteManager
        
        Logger.log("PlaybackManager initializing", category: .lifecycle)
        
        setupObservers()
        startPeriodicUpdates()
        
        Logger.log("PlaybackManager initialized", category: .lifecycle)
    }
    
    deinit {
        Logger.log("PlaybackManager deinitializing", category: .lifecycle)
        cleanup()
    }
    
    // MARK: - Setup Methods
    
    private func setupObservers() {
        // Monitor playback state changes
        $playbackState
            .removeDuplicates()
            .sink { [weak self] state in
                self?.handlePlaybackStateChange(state)
            }
            .store(in: &cancellables)
        
        // Monitor volume changes
        $volume
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { volume in
                Logger.log("Volume changed: \(Int(volume * 100))%", category: .debug)
            }
            .store(in: &cancellables)
    }
    
    private func startPeriodicUpdates() {
        stateUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updatePlaybackInfo()
            }
        }
    }
    
    private func updatePlaybackInfo() async {
        // This would typically fetch current playback info from the media remote
        // For now, we'll implement basic state tracking
        
        // Update current time if playing
        if playbackState == .playing {
            currentTime += 1.0
        }
    }
    
    private func handlePlaybackStateChange(_ state: PlaybackState) {
        switch state {
        case .playing:
            Logger.log("Playback started", category: .debug)
        case .paused:
            Logger.log("Playback paused", category: .debug)
        case .stopped:
            Logger.log("Playback stopped", category: .debug)
            currentTime = 0
        case .interrupted:
            Logger.log("Playback interrupted", category: .warning)
        case .buffering:
            Logger.log("Playback buffering", category: .debug)
        case .unknown:
            break
        }
    }
    
    // MARK: - Public Control Methods
    
    func playPause() -> Bool {
        Logger.log("Toggle play/pause requested", category: .debug)
        
        let command: MediaRemoteCommand = isPlaying ? .pause : .play
        
        Task {
            do {
                try await executeCommand(command)
                await MainActor.run {
                    self.playbackState = self.isPlaying ? .paused : .playing
                }
            } catch {
                await MainActor.run {
                    self.handleCommandError(error, command: command)
                }
            }
        }
        
        return !isPlaying
    }
    
    func play() {
        Logger.log("Play requested", category: .debug)
        
        Task {
            do {
                try await executeCommand(.play)
                await MainActor.run {
                    self.playbackState = .playing
                }
            } catch {
                await MainActor.run {
                    self.handleCommandError(error, command: .play)
                }
            }
        }
    }
    
    func pause() {
        Logger.log("Pause requested", category: .debug)
        
        Task {
            do {
                try await executeCommand(.pause)
                await MainActor.run {
                    self.playbackState = .paused
                }
            } catch {
                await MainActor.run {
                    self.handleCommandError(error, command: .pause)
                }
            }
        }
    }
    
    func stop() {
        Logger.log("Stop requested", category: .debug)
        
        Task {
            do {
                try await executeCommand(.stop)
                await MainActor.run {
                    self.playbackState = .stopped
                    self.currentTime = 0
                }
            } catch {
                await MainActor.run {
                    self.handleCommandError(error, command: .stop)
                }
            }
        }
    }
    
    func nextTrack() {
        Logger.log("Next track requested", category: .debug)
        
        Task {
            do {
                try await executeCommand(.nextTrack)
                await MainActor.run {
                    self.currentTime = 0
                }
            } catch {
                await MainActor.run {
                    self.handleCommandError(error, command: .nextTrack)
                }
            }
        }
    }
    
    func previousTrack() {
        Logger.log("Previous track requested", category: .debug)
        
        Task {
            do {
                try await executeCommand(.previousTrack)
                await MainActor.run {
                    self.currentTime = 0
                }
            } catch {
                await MainActor.run {
                    self.handleCommandError(error, command: .previousTrack)
                }
            }
        }
    }
    
    func seekTrack(to time: TimeInterval) {
        guard time >= 0 && (duration == 0 || time <= duration) else {
            Logger.log("Invalid seek time: \(time)", category: .error)
            lastError = .invalidSeekTime(time)
            return
        }
        
        Logger.log("Seek to \(time) requested", category: .debug)
        
        Task {
            do {
                try await mediaRemoteManager.setElapsedTime(time)
                await MainActor.run {
                    self.currentTime = time
                }
            } catch {
                await MainActor.run {
                    self.lastError = .executionFailed(.seekForward, error.localizedDescription)
                }
            }
        }
    }
    
    func seekForward(_ interval: TimeInterval = 15) {
        let newTime = min(currentTime + interval, duration)
        seekTrack(to: newTime)
    }
    
    func seekBackward(_ interval: TimeInterval = 15) {
        let newTime = max(currentTime - interval, 0)
        seekTrack(to: newTime)
    }
    
    func setVolume(_ volume: Double) {
        guard volume >= 0 && volume <= 1 else {
            Logger.log("Invalid volume: \(volume)", category: .error)
            lastError = .invalidVolume(volume)
            return
        }
        
        Logger.log("Set volume to \(Int(volume * 100))%", category: .debug)
        
        Task {
            do {
                try await executeCommand(.changeVolume, parameter: volume)
                await MainActor.run {
                    self.volume = volume
                }
            } catch {
                await MainActor.run {
                    self.handleCommandError(error, command: .changeVolume)
                }
            }
        }
    }
    
    func setPlaybackRate(_ rate: Double) {
        Logger.log("Set playback rate to \(rate)x", category: .debug)
        
        Task {
            do {
                try await executeCommand(.changePlaybackRate, parameter: rate)
                await MainActor.run {
                    self.playbackRate = rate
                }
            } catch {
                await MainActor.run {
                    self.handleCommandError(error, command: .changePlaybackRate)
                }
            }
        }
    }
    
    // MARK: - Command Execution
    
    private func executeCommand(_ command: MediaRemoteCommand, parameter: Any? = nil) async throws {
        guard !pendingCommands.contains(command) else {
            Logger.log("Command \(command.displayName) already pending", category: .warning)
            return
        }
        
        pendingCommands.insert(command)
        defer { pendingCommands.remove(command) }
        
        let attemptCount = commandExecutionCount[command, default: 0]
        guard attemptCount < maxRetryAttempts else {
            throw PlaybackError.executionFailed(command, "Max retry attempts exceeded")
        }
        
        commandExecutionCount[command] = attemptCount + 1
        
        return try await withCheckedThrowingContinuation { continuation in
            commandQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: PlaybackError.mediaRemoteFrameworkNotLoaded)
                    return
                }
                
                do {
                    try self.mediaRemoteManager.sendCommand(command.rawValue, parameter: parameter)
                    
                    // Reset retry count on success
                    DispatchQueue.main.async {
                        self.commandExecutionCount[command] = 0
                    }
                    
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: PlaybackError.executionFailed(command, error.localizedDescription))
                }
            }
        }
    }
    
    private func handleCommandError(_ error: Error, command: MediaRemoteCommand) {
        if let playbackError = error as? PlaybackError {
            lastError = playbackError
        } else {
            lastError = .executionFailed(command, error.localizedDescription)
        }
        
        Logger.log("Command error: \(error.localizedDescription)", category: .error)
    }
    
    // MARK: - State Management
    
    func updatePlaybackState(_ state: PlaybackState) {
        guard state != playbackState else { return }
        playbackState = state
    }
    
    func updateCurrentTime(_ time: TimeInterval) {
        currentTime = time
    }
    
    func updateDuration(_ duration: TimeInterval) {
        self.duration = duration
    }
    
    // MARK: - Error Handling
    
    func clearError() {
        lastError = nil
    }
    
    func retryLastCommand() {
        // Implementation would retry the last failed command
        // For now, we'll just clear the error
        clearError()
    }
    
    // MARK: - Cleanup
    
    private func cleanup() {
        stateUpdateTimer?.invalidate()
        stateUpdateTimer = nil
        
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        
        pendingCommands.removeAll()
        commandExecutionCount.removeAll()
        
        Logger.log("PlaybackManager cleanup completed", category: .lifecycle)
        Logger.trackMemory()
    }
}

// MARK: - Convenience Extensions

extension PlaybackManager {
    
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    var remainingTime: TimeInterval {
        return max(0, duration - currentTime)
    }
    
    var formattedCurrentTime: String {
        return formatTime(currentTime)
    }
    
    var formattedDuration: String {
        return formatTime(duration)
    }
    
    var formattedRemainingTime: String {
        return formatTime(remainingTime)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    var canSeekForward: Bool {
        currentTime < duration
    }
    
    var canSeekBackward: Bool {
        currentTime > 0
    }
    
    var hasContent: Bool {
        duration > 0
    }
}

// MARK: - MediaRemoteManager Extension

extension MediaRemoteManager {
    
    func sendCommand(_ command: Int, parameter: Any? = nil) throws {
        // Implementation depends on the actual MediaRemote framework binding
        // This is a placeholder for the actual command execution
        Logger.log("Sending media remote command: \(command)", category: .debug)
        
        // Use the existing function pointers from the main implementation
        if let sendCommandFunction = self.MrMediaRemoteSendCommandFunction {
            sendCommandFunction(command, parameter as AnyObject?)
        } else {
            throw PlaybackError.mediaRemoteFrameworkNotLoaded
        }
    }
    
    func setElapsedTime(_ time: TimeInterval) async throws {
        Logger.log("Setting elapsed time: \(time)", category: .debug)
        
        return try await withCheckedThrowingContinuation { continuation in
            if let setElapsedTimeFunction = self.MrMediaRemoteSetElapsedTimeFunction {
                setElapsedTimeFunction(time)
                continuation.resume()
            } else {
                continuation.resume(throwing: PlaybackError.mediaRemoteFrameworkNotLoaded)
            }
        }
    }
}

// MARK: - Debug Extensions

#if DEBUG
extension PlaybackManager {
    
    func debugPrintState() {
        print("""
        PlaybackManager Debug State:
        - Playback State: \(playbackState.displayName)
        - Is Playing: \(isPlaying)
        - Current Time: \(formattedCurrentTime)
        - Duration: \(formattedDuration)
        - Progress: \(Int(progress * 100))%
        - Volume: \(Int(volume * 100))%
        - Playback Rate: \(playbackRate)x
        - Last Error: \(lastError?.localizedDescription ?? "None")
        - Pending Commands: \(pendingCommands.map { $0.displayName })
        """)
    }
    
    func simulatePlayback() {
        // Simulate playback for testing
        playbackState = .playing
        duration = 180 // 3 minutes
        currentTime = 30 // 30 seconds in
        volume = 0.7
        playbackRate = 1.0
        
        Logger.log("Simulated playback state set", category: .debug)
    }
    
    func simulateError() {
        lastError = .executionFailed(.play, "Simulated error for testing")
        Logger.log("Simulated error set", category: .debug)
    }
}
#endif

// MARK: - SwiftUI Integration

extension PlaybackManager {
    
    var playPauseButtonImage: String {
        switch playbackState {
        case .playing:
            return "pause.fill"
        case .paused, .stopped:
            return "play.fill"
        case .buffering:
            return "ellipsis"
        case .interrupted:
            return "exclamationmark.triangle.fill"
        case .unknown:
            return "questionmark"
        }
    }
    
    var volumeIcon: String {
        if volume == 0 {
            return "speaker.slash.fill"
        } else if volume < 0.33 {
            return "speaker.fill"
        } else if volume < 0.66 {
            return "speaker.wave.1.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
    
    var playbackRateText: String {
        if playbackRate == 1.0 {
            return "1×"
        } else {
            return String(format: "%.1f×", playbackRate)
        }
    }
}