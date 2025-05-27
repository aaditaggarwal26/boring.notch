import SwiftUI
import QuartzCore

// MARK: - Apple Animation Curves

struct AppleAnimationCurves {
    
    // Core Apple animation timings
    static let easeInOut = Animation.timingCurve(0.4, 0.0, 0.2, 1.0)
    static let easeOut = Animation.timingCurve(0.0, 0.0, 0.2, 1.0)
    static let easeIn = Animation.timingCurve(0.4, 0.0, 1.0, 1.0)
    static let linear = Animation.linear
    
    // Apple's signature spring animations
    static let defaultSpring = Animation.spring(
        response: 0.5,
        dampingFraction: 0.8,
        blendDuration: 0.1
    )
    
    static let bouncySpring = Animation.spring(
        response: 0.6,
        dampingFraction: 0.7,
        blendDuration: 0.1
    )
    
    static let gentleSpring = Animation.spring(
        response: 0.4,
        dampingFraction: 0.9,
        blendDuration: 0.05
    )
    
    static let snappySpring = Animation.spring(
        response: 0.3,
        dampingFraction: 0.85,
        blendDuration: 0.05
    )
    
    // macOS-specific animations
    static let windowOpen = Animation.spring(
        response: 0.55,
        dampingFraction: 0.825,
        blendDuration: 0.1
    )
    
    static let windowClose = Animation.spring(
        response: 0.4,
        dampingFraction: 0.9,
        blendDuration: 0.05
    )
    
    static let hoverResponse = Animation.spring(
        response: 0.25,
        dampingFraction: 0.8,
        blendDuration: 0.02
    )
    
    static let contentSlide = Animation.spring(
        response: 0.45,
        dampingFraction: 0.85,
        blendDuration: 0.08
    )
    
    // Notification-style animations
    static let notification = Animation.spring(
        response: 0.7,
        dampingFraction: 0.8,
        blendDuration: 0.1
    )
    
    static let dismissal = Animation.spring(
        response: 0.35,
        dampingFraction: 0.95,
        blendDuration: 0.05
    )
    
    // System-wide timings
    static func systemTiming(duration: Double) -> Animation {
        return .timingCurve(0.25, 0.1, 0.25, 1.0, duration: duration)
    }
    
    static func customSpring(
        response: Double = 0.5,
        dampingFraction: Double = 0.8,
        blendDuration: Double = 0.1
    ) -> Animation {
        return .spring(
            response: response,
            dampingFraction: dampingFraction,
            blendDuration: blendDuration
        )
    }
}

// MARK: - Native Animation Manager

@MainActor
class NativeAnimationManager: ObservableObject {
    
    static let shared = NativeAnimationManager()
    
    @Published var isReducedMotionEnabled: Bool = false
    @Published var animationScale: Double = 1.0
    
    private init() {
        checkAccessibilitySettings()
        setupAccessibilityObserver()
    }
    
    private func checkAccessibilitySettings() {
        isReducedMotionEnabled = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        animationScale = isReducedMotionEnabled ? 0.3 : 1.0
    }
    
    private func setupAccessibilityObserver() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkAccessibilitySettings()
        }
    }
    
    func animation(_ baseAnimation: Animation) -> Animation {
        if isReducedMotionEnabled {
            return .linear(duration: 0.2)
        }
        return baseAnimation.speed(animationScale)
    }
    
    func duration(_ baseDuration: Double) -> Double {
        return isReducedMotionEnabled ? 0.2 : baseDuration * animationScale
    }
}

// MARK: - Native Transitions

struct NativeTransitions {
    
    // Slide transitions with Apple's easing
    static var slideUp: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom)
                .combined(with: .opacity)
                .animation(AppleAnimationCurves.windowOpen),
            removal: .move(edge: .bottom)
                .combined(with: .opacity)
                .animation(AppleAnimationCurves.windowClose)
        )
    }
    
    static var slideDown: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top)
                .combined(with: .opacity)
                .animation(AppleAnimationCurves.windowOpen),
            removal: .move(edge: .top)
                .combined(with: .opacity)
                .animation(AppleAnimationCurves.windowClose)
        )
    }
    
    static var slideLeft: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing)
                .combined(with: .opacity)
                .animation(AppleAnimationCurves.contentSlide),
            removal: .move(edge: .leading)
                .combined(with: .opacity)
                .animation(AppleAnimationCurves.contentSlide)
        )
    }
    
    static var slideRight: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .leading)
                .combined(with: .opacity)
                .animation(AppleAnimationCurves.contentSlide),
            removal: .move(edge: .trailing)
                .combined(with: .opacity)
                .animation(AppleAnimationCurves.contentSlide)
        )
    }
    
    // Scale transitions
    static var scaleAndFade: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.8)
                .combined(with: .opacity)
                .animation(AppleAnimationCurves.bouncySpring),
            removal: .scale(scale: 0.9)
                .combined(with: .opacity)
                .animation(AppleAnimationCurves.dismissal)
        )
    }
    
    // Notification-style
    static var notificationSlide: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top)
                .combined(with: .scale(scale: 0.95))
                .combined(with: .opacity)
                .animation(AppleAnimationCurves.notification),
            removal: .move(edge: .top)
                .combined(with: .opacity)
                .animation(AppleAnimationCurves.dismissal)
        )
    }
    
    // Blur replace with scale
    static var blurReplace: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 1.05)
                .combined(with: .opacity)
                .animation(AppleAnimationCurves.gentleSpring),
            removal: .scale(scale: 0.95)
                .combined(with: .opacity)
                .animation(AppleAnimationCurves.dismissal)
        )
    }
    
    // Push transition
    static func push(from edge: Edge) -> AnyTransition {
        switch edge {
        case .top:
            return slideDown
        case .bottom:
            return slideUp
        case .leading:
            return slideRight
        case .trailing:
            return slideLeft
        }
    }
}

// MARK: - Native Effect Modifiers

struct NativeHoverEffect: ViewModifier {
    @State private var isHovered = false
    @State private var hoverProgress: CGFloat = 0
    
    let scaleEffect: CGFloat
    let shadowRadius: CGFloat
    let shadowOffset: CGFloat
    
    init(
        scaleEffect: CGFloat = 1.02,
        shadowRadius: CGFloat = 8,
        shadowOffset: CGFloat = 2
    ) {
        self.scaleEffect = scaleEffect
        self.shadowRadius = shadowRadius
        self.shadowOffset = shadowOffset
    }
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(1 + (scaleEffect - 1) * hoverProgress)
            .shadow(
                color: .black.opacity(0.15 * hoverProgress),
                radius: shadowRadius * hoverProgress,
                y: shadowOffset * hoverProgress
            )
            .onHover { hovering in
                withAnimation(AppleAnimationCurves.hoverResponse) {
                    isHovered = hovering
                    hoverProgress = hovering ? 1 : 0
                }
            }
    }
}

struct NativePressEffect: ViewModifier {
    @State private var isPressed = false
    
    let scaleEffect: CGFloat
    let opacity: Double
    
    init(scaleEffect: CGFloat = 0.95, opacity: Double = 0.8) {
        self.scaleEffect = scaleEffect
        self.opacity = opacity
    }
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? scaleEffect : 1.0)
            .opacity(isPressed ? opacity : 1.0)
            .onLongPressGesture(
                minimumDuration: 0,
                maximumDistance: .infinity,
                pressing: { pressing in
                    withAnimation(AppleAnimationCurves.snappySpring) {
                        isPressed = pressing
                    }
                },
                perform: {}
            )
    }
}

struct NativeGlowEffect: ViewModifier {
    let color: Color
    let radius: CGFloat
    let intensity: Double
    
    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(intensity), radius: radius)
            .shadow(color: color.opacity(intensity * 0.7), radius: radius * 0.7)
            .shadow(color: color.opacity(intensity * 0.4), radius: radius * 0.4)
    }
}

// MARK: - Animated Background Blur

struct AnimatedBackgroundBlur: ViewModifier {
    let radius: CGFloat
    let opacity: Double
    
    func body(content: Content) -> some View {
        content
            .background(
                VisualEffectView(
                    material: .hudWindow,
                    blendingMode: .behindWindow,
                    emphasized: true
                )
                .opacity(opacity)
            )
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let emphasized: Bool
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.isEmphasized = emphasized
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.isEmphasized = emphasized
    }
}

// MARK: - Breathing Animation

struct BreathingAnimation: ViewModifier {
    @State private var scale: CGFloat = 1.0
    
    let minScale: CGFloat
    let maxScale: CGFloat
    let duration: Double
    
    init(
        minScale: CGFloat = 0.98,
        maxScale: CGFloat = 1.02,
        duration: Double = 3.0
    ) {
        self.minScale = minScale
        self.maxScale = maxScale
        self.duration = duration
    }
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: duration)
                    .repeatForever(autoreverses: true)
                ) {
                    scale = maxScale
                }
            }
    }
}

// MARK: - Pulse Animation

struct PulseAnimation: ViewModifier {
    @State private var opacity: Double = 1.0
    
    let minOpacity: Double
    let maxOpacity: Double
    let duration: Double
    
    init(
        minOpacity: Double = 0.6,
        maxOpacity: Double = 1.0,
        duration: Double = 1.5
    ) {
        self.minOpacity = minOpacity
        self.maxOpacity = maxOpacity
        self.duration = duration
    }
    
    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: duration)
                    .repeatForever(autoreverses: true)
                ) {
                    opacity = minOpacity
                }
            }
    }
}

// MARK: - Shimmer Effect

struct ShimmerEffect: ViewModifier {
    @State private var shimmerOffset: CGFloat = -1
    
    let gradient = LinearGradient(
        colors: [
            .clear,
            .white.opacity(0.3),
            .clear
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Rectangle()
                    .fill(gradient)
                    .offset(x: shimmerOffset * 300)
                    .blur(radius: 1)
            )
            .clipped()
            .onAppear {
                withAnimation(
                    .linear(duration: 2.0)
                    .repeatForever(autoreverses: false)
                ) {
                    shimmerOffset = 1
                }
            }
    }
}

// MARK: - View Extensions

extension View {
    
    func nativeHoverEffect(
        scaleEffect: CGFloat = 1.02,
        shadowRadius: CGFloat = 8,
        shadowOffset: CGFloat = 2
    ) -> some View {
        modifier(NativeHoverEffect(
            scaleEffect: scaleEffect,
            shadowRadius: shadowRadius,
            shadowOffset: shadowOffset
        ))
    }
    
    func nativePressEffect(
        scaleEffect: CGFloat = 0.95,
        opacity: Double = 0.8
    ) -> some View {
        modifier(NativePressEffect(
            scaleEffect: scaleEffect,
            opacity: opacity
        ))
    }
    
    func nativeGlow(
        color: Color = .blue,
        radius: CGFloat = 10,
        intensity: Double = 0.6
    ) -> some View {
        modifier(NativeGlowEffect(
            color: color,
            radius: radius,
            intensity: intensity
        ))
    }
    
    func animatedBlur(
        radius: CGFloat = 10,
        opacity: Double = 0.8
    ) -> some View {
        modifier(AnimatedBackgroundBlur(
            radius: radius,
            opacity: opacity
        ))
    }
    
    func breathing(
        minScale: CGFloat = 0.98,
        maxScale: CGFloat = 1.02,
        duration: Double = 3.0
    ) -> some View {
        modifier(BreathingAnimation(
            minScale: minScale,
            maxScale: maxScale,
            duration: duration
        ))
    }
    
    func pulse(
        minOpacity: Double = 0.6,
        maxOpacity: Double = 1.0,
        duration: Double = 1.5
    ) -> some View {
        modifier(PulseAnimation(
            minOpacity: minOpacity,
            maxOpacity: maxOpacity,
            duration: duration
        ))
    }
    
    func shimmer() -> some View {
        modifier(ShimmerEffect())
    }
    
    func nativeAnimation(_ animation: Animation) -> some View {
        let manager = NativeAnimationManager.shared
        return self.animation(manager.animation(animation))
    }
    
    func nativeTransition(_ transition: AnyTransition) -> some View {
        self.transition(transition)
    }
    
    // Convenience methods for common animations
    func slideInFromBottom() -> some View {
        self.transition(NativeTransitions.slideUp)
    }
    
    func slideInFromTop() -> some View {
        self.transition(NativeTransitions.slideDown)
    }
    
    func scaleAndFadeIn() -> some View {
        self.transition(NativeTransitions.scaleAndFade)
    }
    
    func notificationStyle() -> some View {
        self.transition(NativeTransitions.notificationSlide)
    }
    
    // Chain multiple native effects
    func nativeButtonStyle() -> some View {
        self
            .nativeHoverEffect(scaleEffect: 1.03)
            .nativePressEffect(scaleEffect: 0.97)
    }
    
    func nativeCardStyle() -> some View {
        self
            .nativeHoverEffect(scaleEffect: 1.02, shadowRadius: 12, shadowOffset: 4)
            .animatedBlur(radius: 8, opacity: 0.9)
    }
}

// MARK: - Haptic Feedback Integration

struct NativeHapticFeedback {
    
    static func light() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .default
        )
    }
    
    static func medium() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .default
        )
    }
    
    static func heavy() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .default
        )
    }
    
    static func selection() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .default
        )
    }
    
    static func success() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .default
        )
    }
    
    static func error() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .default
        )
    }
}

// MARK: - Animation State Manager

@MainActor
class AnimationStateManager: ObservableObject {
    
    @Published var isAnimating = false
    @Published var animationProgress: Double = 0
    
    private var animationTimer: Timer?
    private var startTime: Date?
    
    func startAnimation(duration: TimeInterval, completion: @escaping () -> Void = {}) {
        stopAnimation()
        
        isAnimating = true
        animationProgress = 0
        startTime = Date()
        
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] timer in
            guard let self = self, let startTime = self.startTime else {
                timer.invalidate()
                return
            }
            
            let elapsed = Date().timeIntervalSince(startTime)
            self.animationProgress = min(elapsed / duration, 1.0)
            
            if self.animationProgress >= 1.0 {
                self.stopAnimation()
                completion()
            }
        }
    }
    
    func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        isAnimating = false
        animationProgress = 0
        startTime = nil
    }
}