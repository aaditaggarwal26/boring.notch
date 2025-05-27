import SwiftUI

// MARK: - Enhanced System Event Indicator

struct SystemEventIndicatorModifier: ViewModifier {
    @Binding var eventType: SneakContentType
    @Binding var value: CGFloat
    @Binding var icon: String
    let sendEventBack: (SneakContentType) -> Void
    
    @State private var indicatorScale: CGFloat = 0.8
    @State private var indicatorOpacity: Double = 0
    @State private var glowIntensity: Double = 0
    @State private var rippleEffect: Bool = false
    
    @ObservedObject var nativeAnimationManager = NativeAnimationManager.shared
    
    func body(content: Content) -> some View {
        content
            .overlay(
                SystemEventIndicatorView(
                    eventType: eventType,
                    value: value,
                    icon: icon,
                    scale: indicatorScale,
                    opacity: indicatorOpacity,
                    glowIntensity: glowIntensity,
                    rippleEffect: rippleEffect
                )
            )
            .onAppear {
                showIndicator()
            }
            .onDisappear {
                hideIndicator()
            }
    }
    
    private func showIndicator() {
        withAnimation(
            nativeAnimationManager.animation(AppleAnimationCurves.notification)
        ) {
            indicatorScale = 1.0
            indicatorOpacity = 1.0
            glowIntensity = 1.0
        }
        
        // Ripple effect
        withAnimation(
            .easeOut(duration: 0.6).delay(0.1)
        ) {
            rippleEffect = true
        }
        
        // Haptic feedback based on event type
        switch eventType {
        case .volume, .brightness:
            NativeHapticFeedback.light()
        case .battery:
            NativeHapticFeedback.medium()
        default:
            NativeHapticFeedback.light()
        }
    }
    
    private func hideIndicator() {
        withAnimation(
            nativeAnimationManager.animation(AppleAnimationCurves.dismissal)
        ) {
            indicatorScale = 0.9
            indicatorOpacity = 0
            glowIntensity = 0
        }
    }
}

// MARK: - System Event Indicator View

struct SystemEventIndicatorView: View {
    let eventType: SneakContentType
    let value: CGFloat
    let icon: String
    let scale: CGFloat
    let opacity: Double
    let glowIntensity: Double
    let rippleEffect: Bool
    
    @Default(.systemEventIndicatorShadow) var enableShadow
    @Default(.systemEventIndicatorUseAccent) var useAccentColor
    @Default(.enableGradient) var enableGradient
    
    private var indicatorColor: Color {
        if useAccentColor {
            return .accentColor
        }
        
        switch eventType {
        case .volume:
            return .blue
        case .brightness:
            return .yellow
        case .backlight:
            return .orange
        case .battery:
            return value < 20 ? .red : .green
        case .mic:
            return value > 0 ? .green : .red
        default:
            return .blue
        }
    }
    
    private var backgroundGradient: LinearGradient {
        if enableGradient {
            return LinearGradient(
                colors: [
                    indicatorColor,
                    indicatorColor.opacity(0.7)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [indicatorColor, indicatorColor],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Icon with glow effect
            ZStack {
                if rippleEffect {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .stroke(indicatorColor.opacity(0.3), lineWidth: 2)
                            .frame(width: 60 + CGFloat(index) * 20, height: 60 + CGFloat(index) * 20)
                            .scaleEffect(rippleEffect ? 1.5 : 1.0)
                            .opacity(rippleEffect ? 0 : 1)
                            .animation(
                                .easeOut(duration: 1.0).delay(Double(index) * 0.2),
                                value: rippleEffect
                            )
                    }
                }
                
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .frame(width: 60, height: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(indicatorColor.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(
                        color: enableShadow ? indicatorColor.opacity(glowIntensity * 0.5) : .clear,
                        radius: 12,
                        y: 4
                    )
                
                Image(systemName: icon.isEmpty ? eventType.iconName : icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(backgroundGradient)
                    .symbolEffect(.bounce, value: rippleEffect)
            }
            
            // Value indicator
            VStack(spacing: 8) {
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                            )
                            .frame(height: 6)
                        
                        RoundedRectangle(cornerRadius: 3)
                            .fill(backgroundGradient)
                            .frame(
                                width: geometry.size.width * (value / 100),
                                height: 6
                            )
                            .shadow(
                                color: indicatorColor.opacity(glowIntensity * 0.6),
                                radius: 4
                            )
                            .animation(.easeOut(duration: 0.2), value: value)
                    }
                }
                .frame(height: 6)
                
                // Value text
                Text(formatValue())
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            .frame(width: 120)
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .animation(.easeOut(duration: 0.3), value: value)
    }
    
    private func formatValue() -> String {
        switch eventType {
        case .volume, .brightness, .backlight:
            return "\(Int(value))%"
        case .battery:
            return "\(Int(value))%"
        case .mic:
            return value > 0 ? "Unmuted" : "Muted"
        default:
            return "\(Int(value))"
        }
    }
}

// MARK: - Enhanced Inline HUD

struct InlineHUD: View {
    @Binding var type: SneakContentType
    @Binding var value: CGFloat
    @Binding var icon: String
    @Binding var hoverAnimation: Bool
    @Binding var gestureProgress: CGFloat
    
    @State private var hudScale: CGFloat = 0.9
    @State private var hudOpacity: Double = 0
    @State private var valueAnimation: CGFloat = 0
    
    @ObservedObject var nativeAnimationManager = NativeAnimationManager.shared
    
    private var hudColor: Color {
        switch type {
        case .volume:
            return .blue
        case .brightness:
            return .yellow
        case .backlight:
            return .orange
        case .battery:
            return value < 20 ? .red : .green
        case .mic:
            return value > 0 ? .green : .red
        default:
            return .blue
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .strokeBorder(hudColor.opacity(0.3), lineWidth: 1)
                    )
                
                Image(systemName: icon.isEmpty ? type.iconName : icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(hudColor)
            }
            
            // Progress indicator
            HStack(spacing: 2) {
                ForEach(0..<10, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(
                            index < Int(valueAnimation / 10) ? 
                            hudColor : 
                            Color.white.opacity(0.2)
                        )
                        .frame(width: 3, height: 16)
                        .animation(
                            .easeOut(duration: 0.1).delay(Double(index) * 0.02),
                            value: valueAnimation
                        )
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                )
        )
        .scaleEffect(hudScale)
        .opacity(hudOpacity)
        .onAppear {
            showHUD()
            updateValue()
        }
        .onChange(of: value) { _, newValue in
            updateValue()
        }
    }
    
    private func showHUD() {
        withAnimation(
            nativeAnimationManager.animation(AppleAnimationCurves.notification)
        ) {
            hudScale = 1.0
            hudOpacity = 1.0
        }
        
        NativeHapticFeedback.light()
    }
    
    private func updateValue() {
        withAnimation(.easeOut(duration: 0.3)) {
            valueAnimation = value
        }
    }
}

// MARK: - Battery Indicator View

struct BoringBatteryView: View {
    let batteryPercentage: Float
    let isPluggedIn: Bool
    let batteryWidth: CGFloat
    let isInLowPowerMode: Bool
    let isInitialPlugIn: Bool
    
    @State private var chargingAnimation: Bool = false
    @State private var glowIntensity: Double = 0
    @State private var batteryScale: CGFloat = 1.0
    
    private var batteryColor: Color {
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
    
    private var batteryLevel: CGFloat {
        CGFloat(batteryPercentage / 100)
    }
    
    var body: some View {
        ZStack {
            // Battery outline
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(.white.opacity(0.6), lineWidth: 1.5)
                .frame(width: batteryWidth, height: batteryWidth * 0.6)
            
            // Battery fill
            HStack {
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [
                                batteryColor,
                                batteryColor.opacity(0.8)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: (batteryWidth - 4) * batteryLevel,
                        height: batteryWidth * 0.6 - 4
                    )
                    .shadow(
                        color: batteryColor.opacity(glowIntensity),
                        radius: 4
                    )
                    .animation(.easeOut(duration: 0.5), value: batteryLevel)
                
                Spacer()
            }
            .padding(2)
            .mask(
                RoundedRectangle(cornerRadius: 1)
                    .frame(width: batteryWidth - 4, height: batteryWidth * 0.6 - 4)
            )
            
            // Battery terminal
            RoundedRectangle(cornerRadius: 0.5)
                .fill(.white.opacity(0.6))
                .frame(width: 2, height: batteryWidth * 0.3)
                .offset(x: batteryWidth/2 + 1.5)
            
            // Charging indicator
            if isPluggedIn && chargingAnimation {
                Image(systemName: "bolt.fill")
                    .font(.system(size: batteryWidth * 0.3, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 1)
                    .opacity(chargingAnimation ? 1 : 0)
                    .scaleEffect(chargingAnimation ? 1.2 : 0.8)
                    .animation(
                        .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                        value: chargingAnimation
                    )
            }
            
            // Low power mode indicator
            if isInLowPowerMode {
                Circle()
                    .fill(.yellow)
                    .frame(width: 6, height: 6)
                    .offset(x: -batteryWidth/2 + 3, y: -batteryWidth * 0.3 + 3)
                    .pulse(minOpacity: 0.6, maxOpacity: 1.0, duration: 1.5)
            }
        }
        .scaleEffect(batteryScale)
        .onAppear {
            if isPluggedIn {
                startChargingAnimation()
            }
            
            if isInitialPlugIn {
                celebratePlugIn()
            }
        }
        .onChange(of: isPluggedIn) { _, pluggedIn in
            if pluggedIn {
                startChargingAnimation()
                celebratePlugIn()
            } else {
                stopChargingAnimation()
            }
        }
        .animation(.easeOut(duration: 0.3), value: batteryColor)
    }
    
    private func startChargingAnimation() {
        withAnimation(.easeInOut(duration: 0.5)) {
            chargingAnimation = true
            glowIntensity = 0.6
        }
    }
    
    private func stopChargingAnimation() {
        withAnimation(.easeOut(duration: 0.3)) {
            chargingAnimation = false
            glowIntensity = 0
        }
    }
    
    private func celebratePlugIn() {
        withAnimation(.easeOut(duration: 0.2)) {
            batteryScale = 1.15
        }
        
        withAnimation(.easeOut(duration: 0.3).delay(0.2)) {
            batteryScale = 1.0
        }
        
        NativeHapticFeedback.medium()
    }
}

// MARK: - Minimal Face Features

struct MinimalFaceFeatures: View {
    @State private var eyeBlink: Bool = false
    @State private var mouthAnimation: Double = 0
    
    var body: some View {
        HStack(spacing: 8) {
            // Eyes
            HStack(spacing: 4) {
                Circle()
                    .fill(.white)
                    .frame(width: 3, height: eyeBlink ? 1 : 3)
                    .animation(.easeInOut(duration: 0.15), value: eyeBlink)
                
                Circle()
                    .fill(.white)
                    .frame(width: 3, height: eyeBlink ? 1 : 3)
                    .animation(.easeInOut(duration: 0.15), value: eyeBlink)
            }
            
            Spacer()
                .frame(width: 4)
            
            // Mouth
            RoundedRectangle(cornerRadius: 1)
                .fill(.white)
                .frame(width: 6, height: 2)
                .scaleEffect(x: 1.0 + mouthAnimation * 0.3, y: 1.0)
                .animation(.easeInOut(duration: 0.8), value: mouthAnimation)
        }
        .onAppear {
            startFaceAnimation()
        }
    }
    
    private func startFaceAnimation() {
        // Blinking animation
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.15)) {
                eyeBlink = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    eyeBlink = false
                }
            }
        }
        
        // Subtle mouth animation
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            mouthAnimation = 1.0
        }
    }
}

// MARK: - Notification Banner

struct NotificationBanner: View {
    let title: String
    let message: String
    let type: NotificationType
    @Binding var isVisible: Bool
    
    @State private var offset: CGFloat = -100
    @State private var scale: CGFloat = 0.9
    @State private var opacity: Double = 0
    
    @ObservedObject var nativeAnimationManager = NativeAnimationManager.shared
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(type.color.opacity(0.2))
                    .frame(width: 32, height: 32)
                
                Image(systemName: type.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(type.color)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .offset(y: offset)
        .scaleEffect(scale)
        .opacity(opacity)
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.y < -30 {
                        dismiss()
                    }
                }
        )
        .onChange(of: isVisible) { _, visible in
            if visible {
                show()
            } else {
                dismiss()
            }
        }
    }
    
    private func show() {
        withAnimation(
            nativeAnimationManager.animation(AppleAnimationCurves.notification)
        ) {
            offset = 0
            scale = 1.0
            opacity = 1.0
        }
        
        NativeHapticFeedback.light()
        
        // Auto dismiss after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if isVisible {
                dismiss()
            }
        }
    }
    
    private func dismiss() {
        withAnimation(
            nativeAnimationManager.animation(AppleAnimationCurves.dismissal)
        ) {
            offset = -100
            scale = 0.9
            opacity = 0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isVisible = false
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        SystemEventIndicatorView(
            eventType: .volume,
            value: 75,
            icon: "speaker.wave.2.fill",
            scale: 1.0,
            opacity: 1.0,
            glowIntensity: 1.0,
            rippleEffect: true
        )
        
        InlineHUD(
            type: .constant(.brightness),
            value: .constant(60),
            icon: .constant("sun.max.fill"),
            hoverAnimation: .constant(false),
            gestureProgress: .constant(0)
        )
        
        BoringBatteryView(
            batteryPercentage: 85,
            isPluggedIn: true,
            batteryWidth: 30,
            isInLowPowerMode: false,
            isInitialPlugIn: false
        )
    }
    .padding()
    .background(.black)
}