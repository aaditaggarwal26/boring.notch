import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect

struct ContentView: View {
    @EnvironmentObject var vm: BoringViewModel
    @StateObject var batteryModel: BatteryStatusViewModel
    @EnvironmentObject var musicManager: MusicManager
    @StateObject var webcamManager: WebcamManager = .init()
    @StateObject private var stateManager = NotchStateManager()
    @StateObject private var interactionHandler = NotchInteractionHandler()
    @StateObject private var animationManager = AnimationStateManager()
    
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var nativeAnimationManager = NativeAnimationManager.shared
    
    @Namespace var albumArtNamespace
    @Namespace var notchNamespace
    @Namespace var contentNamespace
    
    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.showNotHumanFace) var showNotHumanFace
    @Default(.useModernCloseAnimation) var useModernCloseAnimation
    @Default(.enableShadow) var enableShadow
    
    var body: some View {
        ZStack(alignment: .top) {
            NotchContainerView(
                stateManager: stateManager,
                interactionHandler: interactionHandler,
                albumArtNamespace: albumArtNamespace,
                notchNamespace: notchNamespace,
                contentNamespace: contentNamespace
            )
            .frame(alignment: .top)
            .background(.black)
            .mask {
                NotchShape(cornerRadius: stateManager.effectiveCornerRadius)
                    .matchedGeometryEffect(id: "notchShape", in: notchNamespace)
                    .drawingGroup()
            }
            .padding(.bottom, vm.notchState == .open ? 30 : 0)
            .animation(
                nativeAnimationManager.animation(
                    useModernCloseAnimation ? 
                    AppleAnimationCurves.windowOpen : 
                    AppleAnimationCurves.bouncySpring
                ), 
                value: vm.notchState
            )
            .animation(
                nativeAnimationManager.animation(AppleAnimationCurves.hoverResponse), 
                value: stateManager.hoverAnimation
            )
            .allowsHitTesting(true)
            .animation(
                nativeAnimationManager.animation(AppleAnimationCurves.gentleSpring), 
                value: stateManager.gestureProgress
            )
            .transition(NativeTransitions.scaleAndFade)
            .modifier(NotchInteractionModifier(
                stateManager: stateManager,
                interactionHandler: interactionHandler
            ))
        }
        .frame(maxWidth: openNotchSize.width, maxHeight: openNotchSize.height, alignment: .top)
        .shadow(
            color: stateManager.shouldShowShadow ? .black.opacity(0.4) : .clear,
            radius: enableShadow ? (Defaults[.cornerRadiusScaling] ? 16 : 8) : 0,
            y: enableShadow ? 4 : 0
        )
        .animation(
            nativeAnimationManager.animation(AppleAnimationCurves.gentleSpring),
            value: stateManager.shouldShowShadow
        )
        .background(DragDetectorView())
        .environmentObject(vm)
        .environmentObject(batteryModel)
        .environmentObject(musicManager)
        .environmentObject(webcamManager)
        .environmentObject(animationManager)
        .trackLifecycle("ContentView")
        .onAppear {
            Logger.log("ContentView appeared", category: .lifecycle)
            stateManager.setup(vm: vm, coordinator: coordinator)
            interactionHandler.setup(vm: vm, coordinator: coordinator)
            
            // Initial animation
            withAnimation(
                nativeAnimationManager.animation(AppleAnimationCurves.windowOpen.delay(0.1))
            ) {
                stateManager.hasAppeared = true
            }
        }
    }
}

// MARK: - Enhanced NotchContainerView
struct NotchContainerView: View {
    @ObservedObject var stateManager: NotchStateManager
    @ObservedObject var interactionHandler: NotchInteractionHandler
    let albumArtNamespace: Namespace.ID
    let notchNamespace: Namespace.ID
    let contentNamespace: Namespace.ID
    
    @EnvironmentObject var vm: BoringViewModel
    @EnvironmentObject var batteryModel: BatteryStatusViewModel
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var animationManager: AnimationStateManager
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var nativeAnimationManager = NativeAnimationManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with enhanced animations
            NotchHeaderView(
                stateManager: stateManager,
                albumArtNamespace: albumArtNamespace,
                notchNamespace: notchNamespace
            )
            .zIndex(2)
            .animation(
                nativeAnimationManager.animation(AppleAnimationCurves.contentSlide),
                value: coordinator.currentView
            )
            
            // Content with smooth transitions
            NotchContentView(
                albumArtNamespace: albumArtNamespace,
                contentNamespace: contentNamespace
            )
            .zIndex(1)
            .allowsHitTesting(vm.notchState == .open)
            .blur(radius: stateManager.contentBlurRadius)
            .opacity(stateManager.contentOpacity)
            .animation(
                nativeAnimationManager.animation(AppleAnimationCurves.gentleSpring),
                value: stateManager.contentBlurRadius
            )
            .animation(
                nativeAnimationManager.animation(AppleAnimationCurves.gentleSpring),
                value: stateManager.contentOpacity
            )
        }
        .padding(.horizontal, stateManager.horizontalPadding)
        .padding([.horizontal, .bottom], stateManager.bottomPadding)
        .animation(
            nativeAnimationManager.animation(AppleAnimationCurves.windowOpen),
            value: stateManager.horizontalPadding
        )
        .animation(
            nativeAnimationManager.animation(AppleAnimationCurves.windowOpen),
            value: stateManager.bottomPadding
        )
    }
}

// MARK: - Enhanced NotchHeaderView
struct NotchHeaderView: View {
    @ObservedObject var stateManager: NotchStateManager
    let albumArtNamespace: Namespace.ID
    let notchNamespace: Namespace.ID
    
    @EnvironmentObject var vm: BoringViewModel
    @EnvironmentObject var batteryModel: BatteryStatusViewModel
    @EnvironmentObject var musicManager: MusicManager
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var nativeAnimationManager = NativeAnimationManager.shared
    
    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.showNotHumanFace) var showNotHumanFace
    @Default(.inlineHUD) var inlineHUD
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if coordinator.firstLaunch {
                    WelcomeAnimationView()
                        .transition(NativeTransitions.scaleAndFade)
                        .id("welcome")
                } else if shouldShowBatteryExpanding {
                    BatteryExpandingView(stateManager: stateManager)
                        .transition(NativeTransitions.slideLeft)
                        .id("battery")
                } else if shouldShowInlineHUD {
                    InlineHUDView(stateManager: stateManager)
                        .transition(NativeTransitions.notificationSlide)
                        .id("hud")
                } else if shouldShowMusicLiveActivity {
                    MusicLiveActivityView(
                        albumArtNamespace: albumArtNamespace,
                        stateManager: stateManager
                    )
                    .transition(NativeTransitions.slideUp)
                    .id("music")
                } else if shouldShowFaceAnimation {
                    FaceAnimationView(stateManager: stateManager)
                        .transition(NativeTransitions.scaleAndFade)
                        .id("face")
                } else if vm.notchState == .open {
                    OpenNotchHeaderView(stateManager: stateManager)
                        .transition(NativeTransitions.slideDown)
                        .id("header")
                } else {
                    ClosedNotchPlaceholder()
                        .transition(.opacity)
                        .id("placeholder")
                }
            }
            .animation(
                nativeAnimationManager.animation(AppleAnimationCurves.contentSlide),
                value: coordinator.firstLaunch
            )
            .animation(
                nativeAnimationManager.animation(AppleAnimationCurves.contentSlide),
                value: vm.expandingView.show
            )
            .animation(
                nativeAnimationManager.animation(AppleAnimationCurves.contentSlide),
                value: coordinator.sneakPeek.show
            )
            .animation(
                nativeAnimationManager.animation(AppleAnimationCurves.contentSlide),
                value: vm.notchState
            )
            
            // Sneak Peek with enhanced animation
            if shouldShowSneakPeek {
                SneakPeekView()
                    .transition(NativeTransitions.notificationSlide)
                    .animation(
                        nativeAnimationManager.animation(AppleAnimationCurves.notification),
                        value: coordinator.sneakPeek.show
                    )
            }
        }
        .conditionalModifier(shouldFixSize) { view in
            view.fixedSize()
        }
        .frame(height: stateManager.headerHeight, alignment: .center)
        .animation(
            nativeAnimationManager.animation(AppleAnimationCurves.gentleSpring),
            value: stateManager.headerHeight
        )
    }
    
    // MARK: - Computed Properties for Header Content
    
    private var shouldShowBatteryExpanding: Bool {
        vm.expandingView.type == .battery && vm.expandingView.show && vm.notchState == .closed
    }
    
    private var shouldShowInlineHUD: Bool {
        coordinator.sneakPeek.show && 
        inlineHUD && 
        coordinator.sneakPeek.type != .music && 
        vm.expandingView.type != .battery
    }
    
    private var shouldShowMusicLiveActivity: Bool {
        !vm.expandingView.show && 
        vm.notchState == .closed && 
        (musicManager.isPlaying || !musicManager.isPlayerIdle) && 
        coordinator.showMusicLiveActivityOnClosed
    }
    
    private var shouldShowFaceAnimation: Bool {
        !vm.expandingView.show && 
        vm.notchState == .closed && 
        (!musicManager.isPlaying && musicManager.isPlayerIdle) && 
        showNotHumanFace
    }
    
    private var shouldShowSneakPeek: Bool {
        coordinator.sneakPeek.show && 
        !inlineHUD &&
        ((coordinator.sneakPeek.type != .music && coordinator.sneakPeek.type != .battery) ||
         (vm.expandingView.type != .battery && vm.notchState == .closed))
    }
    
    private var shouldFixSize: Bool {
        (coordinator.sneakPeek.show && coordinator.sneakPeek.type == .music && vm.notchState == .closed) ||
        (coordinator.sneakPeek.show && coordinator.sneakPeek.type != .music && (musicManager.isPlaying || !musicManager.isPlayerIdle))
    }
}

// MARK: - Enhanced Individual Header Components

struct WelcomeAnimationView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var nativeAnimationManager = NativeAnimationManager.shared
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0
    
    var body: some View {
        VStack {
            Spacer()
            HelloAnimation()
                .frame(width: 200, height: 80)
                .scaleEffect(scale)
                .opacity(opacity)
                .onAppear {
                    withAnimation(
                        nativeAnimationManager.animation(
                            AppleAnimationCurves.bouncySpring.delay(0.3)
                        )
                    ) {
                        scale = 1.0
                        opacity = 1.0
                    }
                    vm.closeHello()
                }
                .padding(.top, 40)
                .padding(.horizontal, 100)
            Spacer()
        }
        .animation(
            nativeAnimationManager.animation(AppleAnimationCurves.windowClose),
            value: BoringViewCoordinator.shared.firstLaunch
        )
    }
}

struct BatteryExpandingView: View {
    @ObservedObject var stateManager: NotchStateManager
    @EnvironmentObject var vm: BoringViewModel
    @EnvironmentObject var batteryModel: BatteryStatusViewModel
    @ObservedObject var nativeAnimationManager = NativeAnimationManager.shared
    
    @State private var slideOffset: CGFloat = -50
    @State private var batteryScale: CGFloat = 0.8
    
    var body: some View {
        HStack(spacing: 0) {
            HStack {
                Text(batteryModel.isInitialPlugIn ? "Plugged In" : "Charging")
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            .offset(x: slideOffset)
            .scaleEffect(batteryScale)
            .onAppear {
                withAnimation(
                    nativeAnimationManager.animation(
                        AppleAnimationCurves.bouncySpring.delay(0.1)
                    )
                ) {
                    slideOffset = 0
                    batteryScale = 1.0
                }
            }
            
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 5)
            
            HStack {
                BoringBatteryView(
                    batteryPercentage: batteryModel.batteryPercentage,
                    isPluggedIn: batteryModel.isPluggedIn,
                    batteryWidth: 30,
                    isInLowPowerMode: batteryModel.isInLowPowerMode,
                    isInitialPlugIn: batteryModel.isInitialPlugIn
                )
                .nativeGlow(
                    color: batteryModel.isInLowPowerMode ? .yellow : .green,
                    radius: 6,
                    intensity: 0.4
                )
            }
            .frame(width: 76, alignment: .trailing)
            .scaleEffect(batteryScale)
            .animation(
                nativeAnimationManager.animation(AppleAnimationCurves.gentleSpring),
                value: batteryModel.batteryPercentage
            )
        }
        .frame(height: stateManager.headerHeight, alignment: .center)
    }
}

struct InlineHUDView: View {
    @ObservedObject var stateManager: NotchStateManager
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var nativeAnimationManager = NativeAnimationManager.shared
    
    @State private var hudScale: CGFloat = 0.9
    @State private var hudOpacity: Double = 0
    
    var body: some View {
        InlineHUD(
            type: $coordinator.sneakPeek.type,
            value: $coordinator.sneakPeek.value,
            icon: $coordinator.sneakPeek.icon,
            hoverAnimation: $stateManager.hoverAnimation,
            gestureProgress: $stateManager.gestureProgress
        )
        .scaleEffect(hudScale)
        .opacity(hudOpacity)
        .onAppear {
            withAnimation(
                nativeAnimationManager.animation(AppleAnimationCurves.notification)
            ) {
                hudScale = 1.0
                hudOpacity = 1.0
            }
        }
        .onDisappear {
            withAnimation(
                nativeAnimationManager.animation(AppleAnimationCurves.dismissal)
            ) {
                hudScale = 0.9
                hudOpacity = 0
            }
        }
        .transition(.asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity),
            removal: .scale(scale: 1.1).combined(with: .opacity)
        ))
    }
}

struct MusicLiveActivityView: View {
    let albumArtNamespace: Namespace.ID
    @ObservedObject var stateManager: NotchStateManager
    
    @EnvironmentObject var vm: BoringViewModel
    @EnvironmentObject var musicManager: MusicManager
    @ObservedObject var nativeAnimationManager = NativeAnimationManager.shared
    
    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.coloredSpectrogram) var coloredSpectrogram
    
    @State private var albumArtScale: CGFloat = 0.8
    @State private var visualizerOpacity: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        HStack {
            // Enhanced Album Art with animations
            HStack {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .background(
                        Image(nsImage: musicManager.albumArt)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    )
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed))
                    .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                    .scaleEffect(albumArtScale * pulseScale)
                    .nativeGlow(
                        color: Color(nsColor: musicManager.avgColor),
                        radius: 4,
                        intensity: musicManager.isPlaying ? 0.6 : 0.2
                    )
                    .frame(
                        width: max(0, vm.closedNotchSize.height - 12),
                        height: max(0, vm.closedNotchSize.height - 12)
                    )
                    .onAppear {
                        withAnimation(
                            nativeAnimationManager.animation(AppleAnimationCurves.bouncySpring)
                        ) {
                            albumArtScale = 1.0
                        }
                        
                        // Subtle pulse animation when playing
                        if musicManager.isPlaying {
                            withAnimation(
                                .easeInOut(duration: 2.0).repeatForever(autoreverses: true)
                            ) {
                                pulseScale = 1.02
                            }
                        }
                    }
                    .animation(
                        nativeAnimationManager.animation(AppleAnimationCurves.gentleSpring),
                        value: musicManager.albumArt
                    )
            }
            .frame(
                width: max(0, vm.closedNotchSize.height - (stateManager.hoverAnimation ? 0 : 12) + stateManager.gestureProgress / 2),
                height: max(0, vm.closedNotchSize.height - (stateManager.hoverAnimation ? 0 : 12))
            )
            
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - 20)
            
            // Enhanced Visualizer
            HStack {
                if useMusicVisualizer {
                    Rectangle()
                        .fill(
                            coloredSpectrogram ? 
                            Color(nsColor: musicManager.avgColor).gradient : 
                            Color.gray.gradient
                        )
                        .frame(width: 50, alignment: .center)
                        .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                        .mask {
                            AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                                .frame(width: 16, height: 12)
                        }
                        .opacity(visualizerOpacity)
                        .onAppear {
                            withAnimation(
                                nativeAnimationManager.animation(
                                    AppleAnimationCurves.gentleSpring.delay(0.2)
                                )
                            ) {
                                visualizerOpacity = 1.0
                            }
                        }
                        .animation(
                            nativeAnimationManager.animation(AppleAnimationCurves.gentleSpring),
                            value: musicManager.avgColor
                        )
                } else {
                    LottieAnimationView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(visualizerOpacity)
                        .onAppear {
                            withAnimation(
                                nativeAnimationManager.animation(
                                    AppleAnimationCurves.gentleSpring.delay(0.2)
                                )
                            ) {
                                visualizerOpacity = 1.0
                            }
                        }
                }
            }
            .frame(
                width: max(0, vm.closedNotchSize.height - (stateManager.hoverAnimation ? 0 : 12) + stateManager.gestureProgress / 2),
                height: max(0, vm.closedNotchSize.height - (stateManager.hoverAnimation ? 0 : 12)),
                alignment: .center
            )
        }
        .frame(height: stateManager.headerHeight, alignment: .center)
        .animation(
            nativeAnimationManager.animation(AppleAnimationCurves.gentleSpring),
            value: musicManager.isPlaying
        )
    }
}

struct FaceAnimationView: View {
    @ObservedObject var stateManager: NotchStateManager
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var nativeAnimationManager = NativeAnimationManager.shared
    
    @State private var faceScale: CGFloat = 0.8
    @State private var eyesBlink: Bool = false
    
    var body: some View {
        HStack {
            HStack {
                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: max(0, vm.closedNotchSize.height - 12),
                        height: max(0, vm.closedNotchSize.height - 12)
                    )
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - 20)
                MinimalFaceFeatures()
                    .scaleEffect(faceScale)
                    .onAppear {
                        withAnimation(
                            nativeAnimationManager.animation(AppleAnimationCurves.bouncySpring)
                        ) {
                            faceScale = 1.0
                        }
                        
                        // Blinking animation
                        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                eyesBlink.toggle()
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    eyesBlink.toggle()
                                }
                            }
                        }
                    }
            }
        }
        .frame(height: stateManager.headerHeight, alignment: .center)
    }
}

struct OpenNotchHeaderView: View {
    @ObservedObject var stateManager: NotchStateManager
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var nativeAnimationManager = NativeAnimationManager.shared
    
    @State private var headerOpacity: Double = 0
    @State private var headerOffset: CGFloat = -10
    
    var body: some View {
        BoringHeader()
            .frame(height: max(24, vm.closedNotchSize.height))
            .blur(radius: stateManager.headerBlurRadius)
            .opacity(headerOpacity)
            .offset(y: headerOffset)
            .onAppear {
                withAnimation(
                    nativeAnimationManager.animation(
                        AppleAnimationCurves.contentSlide.delay(0.1)
                    )
                ) {
                    headerOpacity = 1.0
                    headerOffset = 0
                }
            }
            .animation(
                nativeAnimationManager.animation(AppleAnimationCurves.gentleSpring),
                value: vm.notchState
            )
    }
}

struct ClosedNotchPlaceholder: View {
    @EnvironmentObject var vm: BoringViewModel
    
    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: vm.closedNotchSize.width - 20, height: vm.closedNotchSize.height)
    }
}

struct SneakPeekView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @EnvironmentObject var vm: BoringViewModel
    @EnvironmentObject var musicManager: MusicManager
    @ObservedObject var nativeAnimationManager = NativeAnimationManager.shared
    
    @Default(.inlineHUD) var inlineHUD
    
    @State private var sneakPeekScale: CGFloat = 0.9
    @State private var sneakPeekOpacity: Double = 0
    
    var body: some View {
        Group {
            if coordinator.sneakPeek.type != .music && coordinator.sneakPeek.type != .battery {
                SystemEventIndicatorModifier(
                    eventType: $coordinator.sneakPeek.type,
                    value: $coordinator.sneakPeek.value,
                    icon: $coordinator.sneakPeek.icon,
                    sendEventBack: { _ in }
                )
                .scaleEffect(sneakPeekScale)
                .opacity(sneakPeekOpacity)
                .padding(.bottom, 10)
                .padding(.leading, 4)
                .padding(.trailing, 8)
                .onAppear {
                    withAnimation(
                        nativeAnimationManager.animation(AppleAnimationCurves.notification)
                    ) {
                        sneakPeekScale = 1.0
                        sneakPeekOpacity = 1.0
                    }
                }
            } else if vm.expandingView.type != .battery && vm.notchState == .closed {
                HStack(alignment: .center) {
                    Image(systemName: "music.note")
                        .font(.caption)
                    GeometryReader { geo in
                        MarqueeText(
                            .constant(musicManager.songTitle + " - " + musicManager.artistName),
                            textColor: .gray,
                            minDuration: 1,
                            frameWidth: geo.size.width
                        )
                    }
                }
                .foregroundStyle(.gray)
                .scaleEffect(sneakPeekScale)
                .opacity(sneakPeekOpacity)
                .padding(.bottom, 10)
                .onAppear {
                    withAnimation(
                        nativeAnimationManager.animation(AppleAnimationCurves.notification)
                    ) {
                        sneakPeekScale = 1.0
                        sneakPeekOpacity = 1.0
                    }
                }
            }
        }
    }
}

// MARK: - Enhanced NotchContentView
struct NotchContentView: View {
    let albumArtNamespace: Namespace.ID
    let contentNamespace: Namespace.ID
    
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var nativeAnimationManager = NativeAnimationManager.shared
    
    @State private var contentOffset: CGFloat = 20
    @State private var contentOpacity: Double = 0
    
    var body: some View {
        ZStack {
            if vm.notchState == .open {
                Group {
                    switch coordinator.currentView {
                    case .home:
                        NotchHomeView(albumArtNamespace: albumArtNamespace)
                            .matchedGeometryEffect(id: "homeView", in: contentNamespace)
                            .transition(NativeTransitions.slideUp)
                    case .shelf:
                        NotchShelfView()
                            .matchedGeometryEffect(id: "shelfView", in: contentNamespace)
                            .transition(NativeTransitions.slideRight)
                    case .calendar:
                        // CalendarView() // Add when implemented
                        Text("Calendar View")
                            .transition(NativeTransitions.slideLeft)
                    case .settings:
                        // SettingsView() // Add when implemented
                        Text("Settings View")
                            .transition(NativeTransitions.slideDown)
                    }
                }
                .offset(y: contentOffset)
                .opacity(contentOpacity)
                .onAppear {
                    withAnimation(
                        nativeAnimationManager.animation(
                            AppleAnimationCurves.contentSlide.delay(0.15)
                        )
                    ) {
                        contentOffset = 0
                        contentOpacity = 1.0
                    }
                }
                .animation(
                    nativeAnimationManager.animation(AppleAnimationCurves.contentSlide),
                    value: coordinator.currentView
                )
            }
        }
    }
}

// MARK: - Enhanced DragDetectorView
struct DragDetectorView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var nativeAnimationManager = NativeAnimationManager.shared
    
    @Default(.boringShelf) var boringShelf
    
    @State private var dragFeedback: CGFloat = 1.0
    
    var body: some View {
        Group {
            if boringShelf {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .scaleEffect(dragFeedback)
                    .onDrop(of: [.data], isTargeted: $vm.dragDetectorTargeting) { _ in true }
                    .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
                        withAnimation(
                            nativeAnimationManager.animation(AppleAnimationCurves.hoverResponse)
                        ) {
                            dragFeedback = isTargeted ? 1.02 : 1.0
                        }
                        handleDropZoneChange(isTargeted)
                    }
            } else {
                EmptyView()
            }
        }
    }
    
    private func handleDropZoneChange(_ isTargeted: Bool) {
        if isTargeted && vm.notchState == .closed {
            coordinator.currentView = .shelf
            withAnimation(
                nativeAnimationManager.animation(AppleAnimationCurves.windowOpen)
            ) {
                vm.open()
            }
        } else if !isTargeted {
            if vm.dropEvent {
                vm.dropEvent = false
                return
            }
            vm.dropEvent = false
            withAnimation(
                nativeAnimationManager.animation(AppleAnimationCurves.windowClose)
            ) {
                vm.close()
            }
        }
    }
}

// MARK: - Enhanced Supporting Types with Animation States

extension NotchStateManager {
    @Published var hasAppeared: Bool = false
}

// MARK: - Enhanced NotchInteractionModifier
struct NotchInteractionModifier: ViewModifier {
    @ObservedObject var stateManager: NotchStateManager
    @ObservedObject var interactionHandler: NotchInteractionHandler
    @ObservedObject var nativeAnimationManager = NativeAnimationManager.shared
    
    @Default(.openNotchOnHover) var openNotchOnHover
    @Default(.enableGestures) var enableGestures
    @Default(.closeGestureEnabled) var closeGestureEnabled
    
    func body(content: Content) -> some View {
        content
            .conditionalModifier(openNotchOnHover) { view in
                view.onHover { hovering in
                    interactionHandler.handleHover(hovering, stateManager: stateManager)
                }
            }
            .conditionalModifier(!openNotchOnHover) { view in
                view
                    .onHover { hovering in
                        withAnimation(
                            nativeAnimationManager.animation(AppleAnimationCurves.hoverResponse)
                        ) {
                            stateManager.hoverAnimation = hovering
                        }
                        if !hovering && stateManager.vm?.notchState == .open {
                            withAnimation(
                                nativeAnimationManager.animation(AppleAnimationCurves.windowClose)
                            ) {
                                stateManager.vm?.close()
                            }
                        }
                    }
                    .nativeButtonStyle()
                    .onTapGesture {
                        NativeHapticFeedback.light()
                        interactionHandler.handleTap()
                    }
                    .conditionalModifier(enableGestures) { view in
                        view.panGesture(direction: .down) { translation, phase in
                            interactionHandler.handlePanGesture(translation, phase, .down, stateManager: stateManager)
                        }
                    }
            }
            .conditionalModifier(closeGestureEnabled && enableGestures) { view in
                view.panGesture(direction: .up) { translation, phase in
                    interactionHandler.handlePanGesture(translation, phase, .up, stateManager: stateManager)
                }
            }
            .sensoryFeedback(.alignment, trigger: interactionHandler.haptics)
            .contextMenu {
                SettingsLink(label: {
                    Text("Settings")
                })
                .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                
                Button("Edit") {
                    let dn = DynamicNotch(content: EditPanelView())
                    dn.toggle()
                }
                #if DEBUG
                .disabled(false)
                #else
                .disabled(true)
                #endif
                .keyboardShortcut("E", modifiers: .command)
            }
    }
}