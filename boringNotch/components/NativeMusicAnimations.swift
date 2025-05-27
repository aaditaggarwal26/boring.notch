import SwiftUI
import AVFoundation

// MARK: - Enhanced Audio Spectrum View

struct AudioSpectrumView: View {
    @Binding var isPlaying: Bool
    
    @State private var amplitudes: [CGFloat] = Array(repeating: 0.2, count: 8)
    @State private var animationTimer: Timer?
    @State private var phase: Double = 0
    
    let barCount = 8
    let maxHeight: CGFloat = 12
    let barWidth: CGFloat = 1.5
    let spacing: CGFloat = 1
    
    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.9),
                                .white.opacity(0.6)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(
                        width: barWidth,
                        height: maxHeight * amplitudes[index]
                    )
                    .animation(
                        .easeInOut(duration: 0.1 + Double(index) * 0.02),
                        value: amplitudes[index]
                    )
            }
        }
        .onChange(of: isPlaying) { _, playing in
            if playing {
                startAnimation()
            } else {
                stopAnimation()
            }
        }
        .onAppear {
            if isPlaying {
                startAnimation()
            }
        }
        .onDisappear {
            stopAnimation()
        }
    }
    
    private func startAnimation() {
        stopAnimation()
        
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.1)) {
                updateAmplitudes()
            }
        }
    }
    
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        
        withAnimation(.easeOut(duration: 0.5)) {
            amplitudes = Array(repeating: 0.2, count: barCount)
        }
    }
    
    private func updateAmplitudes() {
        phase += 0.3
        
        for i in 0..<barCount {
            let baseAmplitude = 0.3
            let variableAmplitude = 0.7
            
            // Create wave-like motion with some randomness
            let waveComponent = sin(phase + Double(i) * 0.5) * 0.5 + 0.5
            let randomComponent = Double.random(in: 0.8...1.2)
            
            amplitudes[i] = baseAmplitude + variableAmplitude * waveComponent * randomComponent
        }
    }
}

// MARK: - Enhanced Lottie Animation View

struct LottieAnimationView: View {
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.8
    
    var body: some View {
        ZStack {
            // Vinyl record effect
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            .white.opacity(0.3),
                            .white.opacity(0.1),
                            .white.opacity(0.3)
                        ],
                        center: .center
                    ),
                    lineWidth: 2
                )
                .frame(width: 12, height: 12)
                .rotationEffect(.degrees(rotation))
                .scaleEffect(scale)
                .opacity(opacity)
            
            // Center dot
            Circle()
                .fill(.white.opacity(0.6))
                .frame(width: 3, height: 3)
        }
        .onAppear {
            withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                scale = 1.1
                opacity = 1.0
            }
        }
    }
}

// MARK: - Album Art Transition View

struct AlbumArtTransition: View {
    let currentImage: NSImage
    let previousImage: NSImage?
    let isTransitioning: Bool
    
    @State private var flipProgress: Double = 0
    @State private var scaleEffect: CGFloat = 1.0
    @State private var shadowRadius: CGFloat = 4
    
    var body: some View {
        ZStack {
            // Previous image (back of flip)
            if let previousImage = previousImage {
                Image(nsImage: previousImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .rotation3DEffect(
                        .degrees(flipProgress < 0.5 ? 0 : 180),
                        axis: (x: 0, y: 1, z: 0)
                    )
                    .opacity(flipProgress < 0.5 ? 1 : 0)
            }
            
            // Current image (front of flip)
            Image(nsImage: currentImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .rotation3DEffect(
                    .degrees(flipProgress < 0.5 ? -180 : 0),
                    axis: (x: 0, y: 1, z: 0)
                )
                .opacity(flipProgress < 0.5 ? 0 : 1)
        }
        .scaleEffect(scaleEffect)
        .shadow(
            color: .black.opacity(0.3),
            radius: shadowRadius,
            y: 2
        )
        .onChange(of: isTransitioning) { _, transitioning in
            if transitioning {
                performFlipTransition()
            }
        }
    }
    
    private func performFlipTransition() {
        withAnimation(.easeInOut(duration: 0.1)) {
            scaleEffect = 1.05
            shadowRadius = 8
        }
        
        withAnimation(.easeInOut(duration: 0.6)) {
            flipProgress = 1.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeOut(duration: 0.2)) {
                scaleEffect = 1.0
                shadowRadius = 4
            }
            flipProgress = 0
        }
    }
}

// MARK: - Music Progress Bar

struct MusicProgressBar: View {
    @Binding var currentTime: TimeInterval
    @Binding var duration: TimeInterval
    let onSeek: (TimeInterval) -> Void
    
    @State private var isDragging: Bool = false
    @State private var dragPosition: CGFloat = 0
    @State private var hoverPosition: CGFloat? = nil
    @State private var progressGlow: Bool = false
    
    private var progress: CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(currentTime / duration)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 4)
                
                // Hover preview
                if let hoverPos = hoverPosition {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: hoverPos, height: 4)
                }
                
                // Progress track
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white,
                                .white.opacity(0.8)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: isDragging ? dragPosition : geometry.size.width * progress,
                        height: 4
                    )
                    .shadow(
                        color: .white.opacity(progressGlow ? 0.8 : 0.3),
                        radius: progressGlow ? 6 : 2
                    )
                    .animation(.easeOut(duration: 0.2), value: progress)
                
                // Drag handle
                if isDragging || hoverPosition != nil {
                    Circle()
                        .fill(.white)
                        .frame(width: 12, height: 12)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .position(
                            x: isDragging ? dragPosition : geometry.size.width * progress,
                            y: geometry.size.height / 2
                        )
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            progressGlow = true
                            NativeHapticFeedback.light()
                        }
                        
                        dragPosition = max(0, min(geometry.size.width, value.location.x))
                        
                        let newTime = Double(dragPosition / geometry.size.width) * duration
                        currentTime = newTime
                    }
                    .onEnded { value in
                        let finalPosition = max(0, min(geometry.size.width, value.location.x))
                        let newTime = Double(finalPosition / geometry.size.width) * duration
                        onSeek(newTime)
                        
                        withAnimation(.easeOut(duration: 0.3)) {
                            isDragging = false
                            progressGlow = false
                        }
                        
                        NativeHapticFeedback.light()
                    }
            )
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.2)) {
                    if hovering && !isDragging {
                        hoverPosition = geometry.size.width * progress
                    } else {
                        hoverPosition = nil
                    }
                }
            }
        }
        .frame(height: 20)
    }
}

// MARK: - Music Control Buttons

struct MusicControlButton: View {
    let icon: String
    let action: () -> Void
    let isEnabled: Bool
    let isPrimary: Bool
    
    init(
        icon: String,
        isEnabled: Bool = true,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.isEnabled = isEnabled
        self.isPrimary = isPrimary
        self.action = action
    }
    
    @State private var isPressed: Bool = false
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        Button(action: {
            NativeHapticFeedback.light()
            action()
        }) {
            ZStack {
                if isPrimary {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                        )
                }
                
                Image(systemName: icon)
                    .font(.system(size: isPrimary ? 18 : 16, weight: .medium))
                    .foregroundColor(.white)
            }
        }
        .frame(width: isPrimary ? 44 : 32, height: isPrimary ? 44 : 32)
        .scaleEffect(scale)
        .opacity(isEnabled ? 1.0 : 0.5)
        .disabled(!isEnabled)
        .onLongPressGesture(
            minimumDuration: 0,
            maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = pressing
                    scale = pressing ? 0.9 : 1.0
                }
            },
            perform: {}
        )
        .nativeHoverEffect(scaleEffect: 1.1)
        .animation(.easeOut(duration: 0.2), value: scale)
    }
}

// MARK: - Volume Control

struct VolumeControl: View {
    @Binding var volume: Double
    let onVolumeChange: (Double) -> Void
    
    @State private var isDragging: Bool = false
    @State private var hoverPosition: CGFloat? = nil
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: volume == 0 ? "speaker.slash" : "speaker")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 16)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 3)
                    
                    // Volume level
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white)
                        .frame(
                            width: geometry.size.width * CGFloat(volume),
                            height: 3
                        )
                        .animation(.easeOut(duration: 0.1), value: volume)
                    
                    // Hover indicator
                    if let hoverPos = hoverPosition {
                        Circle()
                            .fill(Color.white.opacity(0.8))
                            .frame(width: 8, height: 8)
                            .position(x: hoverPos, y: geometry.size.height / 2)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let newVolume = Double(max(0, min(geometry.size.width, value.location.x)) / geometry.size.width)
                            volume = newVolume
                            onVolumeChange(newVolume)
                            
                            if !isDragging {
                                isDragging = true
                                NativeHapticFeedback.light()
                            }
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.2)) {
                        if hovering {
                            hoverPosition = geometry.size.width * CGFloat(volume)
                        } else {
                            hoverPosition = nil
                        }
                    }
                }
            }
            .frame(height: 12)
            
            Image(systemName: "speaker.wave.2")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 16)
        }
        .frame(height: 20)
    }
}

// MARK: - Now Playing Info Display

struct NowPlayingInfo: View {
    let title: String
    let artist: String
    let album: String
    
    @State private var titleOffset: CGFloat = 0
    @State private var shouldScroll: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title with scrolling
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .offset(x: titleOffset)
                    .background(
                        GeometryReader { geometry in
                            Color.clear.onAppear {
                                checkIfScrollNeeded(geometry: geometry)
                            }
                        }
                    )
                Spacer()
            }
            .clipped()
            
            Text("\(artist) • \(album)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .onAppear {
            if shouldScroll {
                startScrollAnimation()
            }
        }
    }
    
    private func checkIfScrollNeeded(geometry: GeometryProxy) {
        // Simple heuristic - if title is long, enable scrolling
        shouldScroll = title.count > 20
    }
    
    private func startScrollAnimation() {
        let scrollDistance: CGFloat = 100
        
        withAnimation(
            .linear(duration: 3.0)
            .delay(2.0)
            .repeatForever(autoreverses: true)
        ) {
            titleOffset = -scrollDistance
        }
    }
}

// MARK: - Music Player Container

struct MusicPlayerView: View {
    @EnvironmentObject var musicManager: MusicManager
    @ObservedObject var nativeAnimationManager = NativeAnimationManager.shared
    
    @State private var showControls: Bool = false
    @State private var volume: Double = 0.7
    
    var body: some View {
        VStack(spacing: 16) {
            // Album art and info
            HStack(spacing: 16) {
                AlbumArtTransition(
                    currentImage: musicManager.albumArt,
                    previousImage: nil,
                    isTransitioning: musicManager.isFlipping
                )
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 8) {
                    NowPlayingInfo(
                        title: musicManager.songTitle,
                        artist: musicManager.artistName,
                        album: musicManager.album
                    )
                    
                    MusicProgressBar(
                        currentTime: $musicManager.elapsedTime,
                        duration: $musicManager.songDuration,
                        onSeek: { time in
                            musicManager.seekTrack(to: time)
                        }
                    )
                }
            }
            
            // Controls
            HStack(spacing: 20) {
                MusicControlButton(
                    icon: "backward.fill",
                    action: { musicManager.previousTrack() }
                )
                
                MusicControlButton(
                    icon: musicManager.isPlaying ? "pause.fill" : "play.fill",
                    isPrimary: true,
                    action: { musicManager.togglePlayPause() }
                )
                
                MusicControlButton(
                    icon: "forward.fill",
                    action: { musicManager.nextTrack() }
                )
                
                Spacer()
                
                VolumeControl(
                    volume: $volume,
                    onVolumeChange: { newVolume in
                        // Handle volume change
                    }
                )
                .frame(width: 80)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                )
        )
        .onHover { hovering in
            withAnimation(
                nativeAnimationManager.animation(AppleAnimationCurves.hoverResponse)
            ) {
                showControls = hovering
            }
        }
    }
}

// MARK: - Preview

#Preview {
    MusicPlayerView()
        .frame(width: 350, height: 120)
        .padding()
        .background(.black)
}