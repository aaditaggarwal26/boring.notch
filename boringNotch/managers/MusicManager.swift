import AppKit
import Combine
import Defaults
import SwiftUI

let defaultImage: NSImage = .init(
    systemSymbolName: "heart.fill",
    accessibilityDescription: "Album Art"
)!

// MARK: - MusicStateProtocol
protocol MusicStateProtocol {
    var isPlaying: Bool { get }
    var songTitle: String { get }
    var artistName: String { get }
    var albumName: String { get }
    var bundleIdentifier: String? { get }
}

// MARK: - MusicManager
@MainActor
class MusicManager: ObservableObject {
    // MARK: - Published Properties
    @Published var songTitle: String = "I'm Handsome"
    @Published var artistName: String = "Me"
    @Published var albumArt: NSImage = defaultImage
    @Published var isPlaying = false
    @Published var musicToggledManually: Bool = false
    @Published var album: String = "Self Love"
    @Published var playbackManager = PlaybackManager()
    @Published var lastUpdated: Date = .init()
    @Published var isPlayerIdle: Bool = true
    @Published var animations: BoringAnimations = .init()
    @Published var avgColor: NSColor = .white
    @Published var bundleIdentifier: String? = nil
    @Published var songDuration: TimeInterval = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var timestampDate: Date = .init()
    @Published var playbackRate: Double = 0
    @Published var usingAppIconForArtwork: Bool = false
    @Published var isFlipping: Bool = false
    @Published var isTransitioning: Bool = false
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private var debounceToggle: DispatchWorkItem?
    private var flipWorkItem: DispatchWorkItem?
    private var transitionWorkItem: DispatchWorkItem?
    private var artworkUpdateWorkItem: DispatchWorkItem?
    private var elapsedTimeTimer: Timer?
    
    private weak var vm: BoringViewModel?
    @ObservedObject var detector: FullscreenMediaDetector
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    
    private var lastMusicItem: MusicItem?
    private var isCurrentlyPlaying: Bool = false
    
    // MARK: - MediaRemote Integration
    private let mediaRemoteManager: MediaRemoteManager
    private let nowPlaying: NowPlaying
    
    // MARK: - Initialization
    init?(vm: BoringViewModel) {
        self.vm = vm
        self._detector = ObservedObject(wrappedValue: FullscreenMediaDetector())
        self.nowPlaying = NowPlaying()
        
        guard let mediaRemoteManager = MediaRemoteManager() else {
            Logger.log("Failed to initialize MediaRemote framework", category: .error)
            return nil
        }
        
        self.mediaRemoteManager = mediaRemoteManager
        
        Logger.log("MusicManager initialized successfully", category: .lifecycle)
        
        setupObservers()
        fetchInitialNowPlayingInfo()
    }
    
    deinit {
        Logger.log("MusicManager deinitializing", category: .lifecycle)
        cleanup()
    }
    
    // MARK: - Setup Methods
    private func setupObservers() {
        setupMediaRemoteObservers()
        setupDetectorObserver()
        setupDistributedNotifications()
        
        Logger.log("Music observers setup completed", category: .lifecycle)
    }
    
    private func setupMediaRemoteObservers() {
        mediaRemoteManager.onNowPlayingInfoChanged = { [weak self] in
            Task { @MainActor in
                self?.fetchNowPlayingInfo()
            }
        }
        
        mediaRemoteManager.onNowPlayingApplicationChanged = { [weak self] in
            Task { @MainActor in
                self?.updateApp()
            }
        }
        
        mediaRemoteManager.onPlaybackStateChanged = { [weak self] isPlaying in
            Task { @MainActor in
                self?.musicIsPaused(state: isPlaying, setIdle: true)
            }
        }
    }
    
    private func setupDetectorObserver() {
        detector.$currentAppInFullScreen
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.fetchNowPlayingInfo(bypass: true, bundle: self?.nowPlaying.appBundleIdentifier)
            }
            .store(in: &cancellables)
    }
    
    private func setupDistributedNotifications() {
        let notificationNames = [
            "com.spotify.client.PlaybackStateChanged",
            "com.apple.Music.playerInfo"
        ]
        
        for name in notificationNames {
            NotificationCenter.default.publisher(for: NSNotification.Name(name))
                .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
                .sink { [weak self] notification in
                    let bundleId = name.contains("spotify") ? "com.spotify.client" : "com.apple.Music"
                    self?.fetchNowPlayingInfo(bundle: bundleId)
                }
                .store(in: &cancellables)
        }
    }
    
    // MARK: - Public Methods
    func updateApp() {
        bundleIdentifier = nowPlaying.appBundleIdentifier ?? "com.apple.Music"
        Logger.log("App updated: \(bundleIdentifier ?? "unknown")", category: .debug)
    }
    
    func fetchNowPlayingInfo(bypass: Bool = false, bundle: String? = nil) {
        guard !musicToggledManually || bypass else { 
            Logger.log("Skipping fetch - music toggled manually", category: .debug)
            return 
        }
        
        updateBundleIdentifier(bundle)
        
        Task {
            do {
                let information = try await mediaRemoteManager.getNowPlayingInfo()
                await processNowPlayingInfo(information)
            } catch {
                Logger.log("Failed to fetch now playing info: \(error)", category: .error)
            }
        }
    }
    
    func togglePlayPause() {
        Logger.log("Toggle play/pause requested", category: .debug)
        musicToggledManually = true
        
        let playState = playbackManager.playPause()
        musicIsPaused(state: playState, bypass: true, setIdle: true)
        
        if playState {
            fetchNowPlayingInfo(bypass: true)
        } else {
            lastUpdated = Date()
        }
        
        // Reset manual toggle after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.musicToggledManually = false
            self?.fetchNowPlayingInfo()
        }
    }
    
    func nextTrack() {
        Logger.log("Next track requested", category: .debug)
        playbackManager.nextTrack()
        fetchNowPlayingInfo(bypass: true)
    }
    
    func previousTrack() {
        Logger.log("Previous track requested", category: .debug)
        playbackManager.previousTrack()
        fetchNowPlayingInfo(bypass: true)
    }
    
    func seekTrack(to time: TimeInterval) {
        Logger.log("Seek to \(time) requested", category: .debug)
        playbackManager.seekTrack(to: time)
    }
    
    func openMusicApp() {
        guard let bundleID = nowPlaying.appBundleIdentifier else {
            Logger.log("Cannot open music app - no bundle identifier", category: .error)
            return
        }
        
        let workspace = NSWorkspace.shared
        if workspace.launchApplication(withBundleIdentifier: bundleID, options: [], additionalEventParamDescriptor: nil, launchIdentifier: nil) {
            Logger.log("Launched app: \(bundleID)", category: .success)
        } else {
            Logger.log("Failed to launch app: \(bundleID)", category: .error)
        }
    }
    
    // MARK: - Private Methods
    private func fetchInitialNowPlayingInfo() {
        if nowPlaying.playing {
            fetchNowPlayingInfo()
        }
    }
    
    private func updateBundleIdentifier(_ bundle: String?) {
        if let bundle = bundle {
            bundleIdentifier = bundle
        }
    }
    
    private func processNowPlayingInfo(_ information: [String: Any]) async {
        let newInfo = extractMusicInfo(from: information)
        let state = information["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Int
        
        await updateMusicState(newInfo: newInfo, state: state)
        
        // Update timing information
        if let elapsedTime = information["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? TimeInterval,
           let timestampDate = information["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date,
           let playbackRate = information["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double {
            
            self.elapsedTime = elapsedTime
            self.timestampDate = timestampDate
            self.playbackRate = playbackRate
        }
    }
    
    private func extractMusicInfo(from information: [String: Any]) -> MusicItem {
        return MusicItem(
            title: information["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? "",
            artist: information["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? "",
            album: information["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? "",
            duration: information["kMRMediaRemoteNowPlayingInfoDuration"] as? TimeInterval ?? lastMusicItem?.duration ?? 0,
            artworkData: information["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
        )
    }
    
    private func updateMusicState(newInfo: MusicItem, state: Int?) async {
        let musicInfoChanged = newInfo.hasInfoChanged(from: lastMusicItem)
        let artworkChanged = newInfo.hasArtworkChanged(from: lastMusicItem)
        
        if artworkChanged || musicInfoChanged {
            await triggerFlipAnimation()
            
            if artworkChanged {
                await updateArtwork(newInfo.artworkData)
                lastMusicItem?.artworkData = newInfo.artworkData
            }
            
            if musicInfoChanged && !newInfo.title.isEmpty && !newInfo.artist.isEmpty {
                updateSneakPeek()
            }
        }
        
        lastMusicItem = newInfo
        
        // Update UI properties
        artistName = newInfo.artist
        songTitle = newInfo.title
        album = newInfo.album
        songDuration = newInfo.duration
        
        // Check playback state
        Task {
            do {
                let isPlaying = try await mediaRemoteManager.getPlaybackState()
                await MainActor.run {
                    self.musicIsPaused(state: isPlaying, setIdle: true)
                }
            } catch {
                Logger.log("Failed to get playback state: \(error)", category: .error)
            }
        }
    }
    
    private func triggerFlipAnimation() async {
        flipWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.isFlipping = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.isFlipping = false
            }
        }
        
        flipWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }
    
    private func updateArtwork(_ artworkData: Data?) async {
        artworkUpdateWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            Task {
                await self?.processArtwork(artworkData)
            }
        }
        
        artworkUpdateWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
    }
    
    private func processArtwork(_ artworkData: Data?) async {
        let (newArt, usingAppIcon) = await getArtworkImage(artworkData)
        
        await MainActor.run {
            self.usingAppIconForArtwork = usingAppIcon
            if let newArt = newArt {
                self.updateAlbumArt(newAlbumArt: newArt)
            }
        }
    }
    
    private func getArtworkImage(_ artworkData: Data?) async -> (NSImage?, Bool) {
        if let artworkData = artworkData,
           let artworkImage = NSImage(data: artworkData) {
            return (artworkImage, false)
        } else if let appIconImage = AppIconAsNSImage(for: bundleIdentifier ?? nowPlaying.appBundleIdentifier ?? "") {
            return (appIconImage, true)
        }
        return (nil, false)
    }
    
    func musicIsPaused(state: Bool, bypass: Bool = false, setIdle: Bool = false) {
        guard !musicToggledManually || bypass else { return }
        
        let previousState = isPlaying
        let hasContent = !songTitle.isEmpty && !artistName.isEmpty
        
        withAnimation(.smooth) {
            self.isPlaying = state
            self.playbackManager.isPlaying = state
            
            Logger.log("Playback state changed to: \(state)", category: .debug)
            
            handleElapsedTimeTimer(isPlaying: state)
            updateFullscreenMediaDetection()
            
            if previousState != state && hasContent {
                updateSneakPeek()
            }
            
            updateIdleState(setIdle: setIdle, state: state)
        }
    }
    
    private func handleElapsedTimeTimer(isPlaying: Bool) {
        if isPlaying {
            startElapsedTimeTimer()
        } else {
            stopElapsedTimeTimer()
            lastUpdated = Date()
        }
    }
    
    private func startElapsedTimeTimer() {
        stopElapsedTimeTimer()
        elapsedTimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying else { return }
            
            let timeSinceTimestamp = Date().timeIntervalSince(self.timestampDate)
            self.elapsedTime = self.elapsedTime + timeSinceTimestamp * self.playbackRate
            self.timestampDate = Date()
        }
    }
    
    private func stopElapsedTimeTimer() {
        elapsedTimeTimer?.invalidate()
        elapsedTimeTimer = nil
        Logger.log("Elapsed time timer stopped", category: .debug)
    }
    
    private func updateFullscreenMediaDetection() {
        if Defaults[.enableFullscreenMediaDetection] {
            vm?.toggleMusicLiveActivity(status: !detector.currentAppInFullScreen)
        }
    }
    
    private func updateSneakPeek() {
        if isPlaying && Defaults[.enableSneakPeek] && !detector.currentAppInFullScreen {
            coordinator.toggleSneakPeek(status: true, type: SneakContentType.music)
        }
    }
    
    private func updateIdleState(setIdle: Bool, state: Bool) {
        if setIdle && state {
            isPlayerIdle = false
            debounceToggle?.cancel()
        } else if setIdle && !state {
            debounceToggle?.cancel()
            
            debounceToggle = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                if self.lastUpdated.timeIntervalSinceNow < -Defaults[.waitInterval] {
                    withAnimation {
                        self.isPlayerIdle = !self.isPlaying
                    }
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + Defaults[.waitInterval], execute: debounceToggle!)
        }
    }
    
    func updateAlbumArt(newAlbumArt: NSImage) {
        withAnimation(.smooth) {
            self.albumArt = newAlbumArt
            if Defaults[.coloredSpectrogram] {
                calculateAverageColor()
            }
        }
    }
    
    func calculateAverageColor() {
        albumArt.averageColor { [weak self] color in
            DispatchQueue.main.async {
                withAnimation(.smooth) {
                    self?.avgColor = color ?? .white
                }
            }
        }
    }
    
    private func cleanup() {
        // Cancel all work items
        debounceToggle?.cancel()
        flipWorkItem?.cancel()
        transitionWorkItem?.cancel()
        artworkUpdateWorkItem?.cancel()
        
        // Stop timer
        stopElapsedTimeTimer()
        
        // Clear cancellables
        cancellables.removeAll()
        
        Logger.log("MusicManager cleanup completed", category: .lifecycle)
        Logger.trackMemory()
    }
}

// MARK: - Supporting Types

struct MusicItem {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    var artworkData: Data?
    
    func hasInfoChanged(from other: MusicItem?) -> Bool {
        guard let other = other else { return true }
        return title != other.title || artist != other.artist || album != other.album
    }
    
    func hasArtworkChanged(from other: MusicItem?) -> Bool {
        return artworkData != nil && artworkData != other?.artworkData
    }
}

// MARK: - MediaRemoteManager
class MediaRemoteManager {
    private let mediaRemoteBundle: CFBundle
    private let MRMediaRemoteGetNowPlayingInfo: @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private let MRMediaRemoteRegisterForNowPlayingNotifications: @convention(c) (DispatchQueue) -> Void
    private let MRMediaRemoteGetNowPlayingApplicationIsPlaying: @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    
    var onNowPlayingInfoChanged: (() -> Void)?
    var onNowPlayingApplicationChanged: (() -> Void)?
    var onPlaybackStateChanged: ((Bool) -> Void)?
    
    init?() {
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")),
              let MRMediaRemoteGetNowPlayingInfoPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString),
              let MRMediaRemoteRegisterForNowPlayingNotificationsPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteRegisterForNowPlayingNotifications" as CFString),
              let MRMediaRemoteGetNowPlayingApplicationIsPlayingPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying" as CFString)
        else {
            Logger.log("Failed to load MediaRemote.framework", category: .error)
            return nil
        }
        
        mediaRemoteBundle = bundle
        MRMediaRemoteGetNowPlayingInfo = unsafeBitCast(MRMediaRemoteGetNowPlayingInfoPointer, to: (@convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void).self)
        MRMediaRemoteRegisterForNowPlayingNotifications = unsafeBitCast(MRMediaRemoteRegisterForNowPlayingNotificationsPointer, to: (@convention(c) (DispatchQueue) -> Void).self)
        MRMediaRemoteGetNowPlayingApplicationIsPlaying = unsafeBitCast(MRMediaRemoteGetNowPlayingApplicationIsPlayingPointer, to: (@convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void).self)
        
        setupNotifications()
        Logger.log("MediaRemoteManager initialized successfully", category: .success)
    }
    
    private func setupNotifications() {
        MRMediaRemoteRegisterForNowPlayingNotifications(DispatchQueue.main)
        
        let notificationNames = [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"
        ]
        
        for name in notificationNames {
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                switch name {
                case "kMRMediaRemoteNowPlayingInfoDidChangeNotification":
                    self?.onNowPlayingInfoChanged?()
                case "kMRMediaRemoteNowPlayingApplicationDidChangeNotification":
                    self?.onNowPlayingApplicationChanged?()
                case "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification":
                    Task {
                        do {
                            let isPlaying = try await self?.getPlaybackState() ?? false
                            await MainActor.run {
                                self?.onPlaybackStateChanged?(isPlaying)
                            }
                        } catch {
                            Logger.log("Failed to get playback state in notification: \(error)", category: .error)
                        }
                    }
                default:
                    break
                }
            }
        }
    }
    
    func getNowPlayingInfo() async throws -> [String: Any] {
        return try await withCheckedThrowingContinuation { continuation in
            MRMediaRemoteGetNowPlayingInfo(DispatchQueue.main) { information in
                continuation.resume(returning: information)
            }
        }
    }
    
    func getPlaybackState() async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            MRMediaRemoteGetNowPlayingApplicationIsPlaying(DispatchQueue.main) { isPlaying in
                continuation.resume(returning: isPlaying)
            }
        }
    }
}

// MARK: - MusicManager Extension for MusicStateProtocol
extension MusicManager: MusicStateProtocol {
    var albumName: String { album }
}