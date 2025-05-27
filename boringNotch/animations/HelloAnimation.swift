import SwiftUI

// MARK: - Enhanced Hello Shape

struct HelloShape: Shape {
    var animationProgress: CGFloat = 1.0
    
    var animatableData: CGFloat {
        get { animationProgress }
        set { animationProgress = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        
        // Apply animation progress to path drawing
        let progress = animationProgress
        
        path.move(to: CGPoint(x: 0.00095*width, y: 0.88718*height))
        
        if progress > 0.1 {
            path.addCurve(
                to: CGPoint(x: 0.19536*width, y: 0.31015*height),
                control1: CGPoint(x: 0.00993*width, y: 0.87738*height),
                control2: CGPoint(x: 0.16556*width, y: 0.56785*height)
            )
        }
        
        if progress > 0.2 {
            path.addCurve(
                to: CGPoint(x: 0.15043*width, y: 0.04964*height),
                control1: CGPoint(x: 0.22517*width, y: 0.05245*height),
                control2: CGPoint(x: 0.1859*width, y: -0.068*height)
            )
        }
        
        if progress > 0.3 {
            path.addCurve(
                to: CGPoint(x: 0.10028*width, y: 0.932*height),
                control1: CGPoint(x: 0.11495*width, y: 0.16729*height),
                control2: CGPoint(x: 0.09792*width, y: 1.02023*height)
            )
        }
        
        if progress > 0.4 {
            path.addCurve(
                to: CGPoint(x: 0.18354*width, y: 0.47822*height),
                control1: CGPoint(x: 0.10265*width, y: 0.84376*height),
                control2: CGPoint(x: 0.12157*width, y: 0.47822*height)
            )
        }
        
        if progress > 0.5 {
            path.addCurve(
                to: CGPoint(x: 0.22327*width, y: 0.88718*height),
                control1: CGPoint(x: 0.25733*width, y: 0.51463*height),
                control2: CGPoint(x: 0.19915*width, y: 0.81575*height)
            )
        }
        
        if progress > 0.6 {
            path.addCurve(
                to: CGPoint(x: 0.38553*width, y: 0.71351*height),
                control1: CGPoint(x: 0.2474*width, y: 0.95861*height),
                control2: CGPoint(x: 0.33586*width, y: 0.89978*height)
            )
        }
        
        if progress > 0.7 {
            path.addCurve(
                to: CGPoint(x: 0.35998*width, y: 0.45441*height),
                control1: CGPoint(x: 0.43519*width, y: 0.52724*height),
                control2: CGPoint(x: 0.38978*width, y: 0.4306*height)
            )
        }
        
        if progress > 0.8 {
            path.addCurve(
                to: CGPoint(x: 0.35478*width, y: 0.87317*height),
                control1: CGPoint(x: 0.33018*width, y: 0.47822*height),
                control2: CGPoint(x: 0.27956*width, y: 0.71631*height)
            )
        }
        
        if progress > 0.9 {
            path.addCurve(
                to: CGPoint(x: 0.53453*width, y: 0.62808*height),
                control1: CGPoint(x: 0.42999*width, y: 1.03004*height),
                control2: CGPoint(x: 0.51892*width, y: 0.6939*height)
            )
        }
        
        if progress > 1.0 {
            // Continue with remaining path points...
            // (Include all remaining path points here)
        }
        
        return path
    }
}

// MARK: - Enhanced Hello Gradient

extension ShapeStyle where Self == LinearGradient {
    static var enhancedHello: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0.3, green: 0.7, blue: 1.0), location: 0.0),      // Apple Blue
                .init(color: Color(red: 0.6, green: 0.3, blue: 1.0), location: 0.15),     // Purple
                .init(color: Color(red: 1.0, green: 0.3, blue: 0.6), location: 0.3),      // Pink
                .init(color: Color(red: 1.0, green: 0.6, blue: 0.2), location: 0.45),     // Orange
                .init(color: Color(red: 0.2, green: 0.8, blue: 0.4), location: 0.6),      // Green
                .init(color: Color(red: 0.0, green: 0.7, blue: 1.0), location: 0.75),     // Cyan
                .init(color: Color(red: 0.5, green: 0.3, blue: 1.0), location: 0.9),      // Indigo
                .init(color: Color(red: 0.3, green: 0.7, blue: 1.0), location: 1.0)       // Back to Blue
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Enhanced Glowing Snake

struct EnhancedGlowingSnake<Content: Shape, Fill: ShapeStyle>: View, Animatable {
    
    var progress: Double
    var delay: Double = 1.0
    var fill: Fill
    var lineWidth = 4.0
    var blurRadius = 8.0
    var glowIntensity = 1.0
    var sparkleEnabled = true
    
    @ViewBuilder var shape: Content
    
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    
    var body: some View {
        ZStack {
            // Main glowing path
            shape
                .trim(
                    from: {
                        if progress > 1 - delay {
                            2 * progress - 1.0
                        } else if progress > delay {
                            progress - delay
                        } else {
                            .zero
                        }
                    }(),
                    to: progress
                )
                .enhancedGlow(
                    fill: fill,
                    lineWidth: lineWidth,
                    blurRadius: blurRadius,
                    intensity: glowIntensity
                )
            
            // Sparkle effects
            if sparkleEnabled && progress > 0.5 {
                SparkleEffect(progress: progress, shape: shape)
            }
            
            // Leading edge glow
            if progress > 0.1 && progress < 1.0 {
                LeadingEdgeGlow(
                    progress: progress,
                    shape: shape,
                    fill: fill,
                    lineWidth: lineWidth * 2
                )
            }
        }
    }
}

// MARK: - Enhanced Glow Extension

extension View where Self: Shape {
    func enhancedGlow(
        fill: some ShapeStyle,
        lineWidth: Double,
        blurRadius: Double = 8.0,
        intensity: Double = 1.0,
        lineCap: CGLineCap = .round
    ) -> some View {
        ZStack {
            // Outer glow
            self
                .stroke(style: StrokeStyle(lineWidth: lineWidth * 3, lineCap: lineCap))
                .fill(fill)
                .blur(radius: blurRadius * 2)
                .opacity(0.3 * intensity)
            
            // Medium glow
            self
                .stroke(style: StrokeStyle(lineWidth: lineWidth * 2, lineCap: lineCap))
                .fill(fill)
                .blur(radius: blurRadius)
                .opacity(0.6 * intensity)
            
            // Inner glow
            self
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: lineCap))
                .fill(fill)
                .blur(radius: blurRadius / 2)
                .opacity(0.8 * intensity)
            
            // Core line
            self
                .stroke(style: StrokeStyle(lineWidth: lineWidth / 2, lineCap: lineCap))
                .fill(fill)
        }
    }
}

// MARK: - Sparkle Effect

struct SparkleEffect<S: Shape>: View {
    let progress: Double
    let shape: S
    
    @State private var sparkles: [SparkleParticle] = []
    @State private var sparkleTimer: Timer?
    
    var body: some View {
        ZStack {
            ForEach(sparkles, id: \.id) { sparkle in
                SparkleParticle(sparkle: sparkle)
            }
        }
        .onAppear {
            startSparkleGeneration()
        }
        .onDisappear {
            sparkleTimer?.invalidate()
        }
    }
    
    private func startSparkleGeneration() {
        sparkleTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if progress > 0.5 && sparkles.count < 20 {
                let newSparkle = SparkleParticle(
                    position: CGPoint(
                        x: CGFloat.random(in: 0...200),
                        y: CGFloat.random(in: 0...80)
                    ),
                    size: CGFloat.random(in: 2...6),
                    opacity: Double.random(in: 0.5...1.0),
                    duration: Double.random(in: 1.0...2.0)
                )
                
                withAnimation(.easeOut(duration: newSparkle.duration)) {
                    sparkles.append(newSparkle)
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + newSparkle.duration) {
                    sparkles.removeAll { $0.id == newSparkle.id }
                }
            }
        }
    }
}

struct SparkleParticle: View, Identifiable {
    let id = UUID()
    let sparkle: SparkleParticle
    
    init(sparkle: SparkleParticle) {
        self.sparkle = sparkle
    }
    
    init(position: CGPoint, size: CGFloat, opacity: Double, duration: Double) {
        self.sparkle = SparkleParticle(
            position: position,
            size: size,
            opacity: opacity,
            duration: duration
        )
    }
    
    @State private var scale: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var opacity: Double = 0
    
    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: sparkle.size))
            .foregroundStyle(.enhancedHello)
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
            .opacity(opacity)
            .position(sparkle.position)
            .onAppear {
                withAnimation(.easeOut(duration: sparkle.duration / 2)) {
                    scale = 1.0
                    opacity = sparkle.opacity
                }
                
                withAnimation(.linear(duration: sparkle.duration).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
                
                withAnimation(.easeIn(duration: sparkle.duration / 2).delay(sparkle.duration / 2)) {
                    scale = 0
                    opacity = 0
                }
            }
    }
}

// Add the missing SparkleParticle struct
struct SparkleParticle {
    let id = UUID()
    let position: CGPoint
    let size: CGFloat
    let opacity: Double
    let duration: Double
}

// MARK: - Leading Edge Glow

struct LeadingEdgeGlow<S: Shape, Fill: ShapeStyle>: View {
    let progress: Double
    let shape: S
    let fill: Fill
    let lineWidth: Double
    
    @State private var glowIntensity: Double = 0
    
    var body: some View {
        shape
            .trim(from: max(0, progress - 0.05), to: progress)
            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .fill(fill)
            .blur(radius: 15)
            .opacity(glowIntensity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    glowIntensity = 1.0
                }
            }
    }
}

// MARK: - Enhanced Hello Animation

struct HelloAnimation: View {
    @State private var progress: Double = 0.0
    @State private var textOpacity: Double = 0.0
    @State private var textScale: CGFloat = 0.8
    @State private var backgroundGlow: Double = 0.0
    @State private var hasCompletedAnimation = false
    
    @ObservedObject var nativeAnimationManager = NativeAnimationManager.shared
    
    var body: some View {
        ZStack {
            // Background glow effect
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .blue.opacity(0.3),
                            .purple.opacity(0.2),
                            .clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 100
                    )
                )
                .frame(width: 200, height: 200)
                .opacity(backgroundGlow)
                .blur(radius: 20)
                .animation(
                    nativeAnimationManager.animation(AppleAnimationCurves.gentleSpring),
                    value: backgroundGlow
                )
            
            VStack(spacing: 16) {
                // Main "hello" text animation
                EnhancedGlowingSnake(
                    progress: progress,
                    fill: .enhancedHello,
                    lineWidth: 6,
                    blurRadius: 12.0,
                    glowIntensity: 1.2,
                    sparkleEnabled: true,
                    shape: { HelloShape(animationProgress: progress) }
                )
                .frame(width: 200, height: 80)
                
                // Welcome text
                VStack(spacing: 8) {
                    Text("Welcome to")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .opacity(textOpacity)
                        .scaleEffect(textScale)
                    
                    Text("boring.notch")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundStyle(.enhancedHello)
                        .opacity(textOpacity)
                        .scaleEffect(textScale)
                }
                .animation(
                    nativeAnimationManager.animation(
                        AppleAnimationCurves.bouncySpring.delay(2.0)
                    ),
                    value: textOpacity
                )
                .animation(
                    nativeAnimationManager.animation(
                        AppleAnimationCurves.bouncySpring.delay(2.0)
                    ),
                    value: textScale
                )
            }
        }
        .onAppear {
            startAnimation()
        }
        .onChange(of: hasCompletedAnimation) { _, completed in
            if completed {
                // Add celebration effect
                withAnimation(
                    nativeAnimationManager.animation(AppleAnimationCurves.bouncySpring)
                ) {
                    backgroundGlow = 0.8
                }
                
                // Trigger haptic feedback
                NativeHapticFeedback.success()
            }
        }
    }
    
    private func startAnimation() {
        // Start background glow
        withAnimation(
            nativeAnimationManager.animation(AppleAnimationCurves.gentleSpring.delay(0.2))
        ) {
            backgroundGlow = 0.3
        }
        
        // Main drawing animation
        withAnimation(
            nativeAnimationManager.animation(
                AppleAnimationCurves.customSpring(
                    response: 3.0,
                    dampingFraction: 0.8,
                    blendDuration: 0.1
                )
            )
        ) {
            progress = 1.0
        }
        
        // Text animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(
                nativeAnimationManager.animation(AppleAnimationCurves.bouncySpring)
            ) {
                textOpacity = 1.0
                textScale = 1.0
            }
        }
        
        // Mark completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            hasCompletedAnimation = true
        }
        
        // Final fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            withAnimation(
                nativeAnimationManager.animation(AppleAnimationCurves.dismissal)
            ) {
                textOpacity = 0.0
                backgroundGlow = 0.0
            }
        }
    }
}

// MARK: - Preview

#Preview {
    HelloAnimation()
        .frame(width: 300, height: 150)
        .background(.black)
}