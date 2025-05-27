import SwiftUI

// MARK: - Native Button Styles

struct NativeButtonStyle: ButtonStyle {
    let style: NativeButtonStyleType
    let size: NativeButtonSize
    
    init(style: NativeButtonStyleType = .primary, size: NativeButtonSize = .medium) {
        self.style = style
        self.size = size
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .padding(size.padding)
            .background(
                RoundedRectangle(cornerRadius: size.cornerRadius)
                    .fill(style.backgroundColor(isPressed: configuration.isPressed))
                    .overlay(
                        RoundedRectangle(cornerRadius: size.cornerRadius)
                            .strokeBorder(style.borderColor, lineWidth: style.borderWidth)
                    )
            )
            .foregroundColor(style.foregroundColor)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(AppleAnimationCurves.snappySpring, value: configuration.isPressed)
            .nativeHoverEffect(scaleEffect: 1.02)
    }
}

enum NativeButtonStyleType {
    case primary
    case secondary
    case destructive
    case ghost
    case selection
    
    var backgroundColor: (Bool) -> Color {
        { isPressed in
            switch self {
            case .primary:
                return isPressed ? .accentColor.opacity(0.8) : .accentColor
            case .secondary:
                return isPressed ? Color(.controlBackgroundColor).opacity(0.6) : Color(.controlBackgroundColor)
            case .destructive:
                return isPressed ? .red.opacity(0.8) : .red
            case .ghost:
                return isPressed ? .clear : .clear
            case .selection:
                return isPressed ? Color(.selectedControlColor).opacity(0.8) : Color(.selectedControlColor)
            }
        }
    }
    
    var foregroundColor: Color {
        switch self {
        case .primary:
            return .white
        case .secondary:
            return .primary
        case .destructive:
            return .white
        case .ghost:
            return .accentColor
        case .selection:
            return .white
        }
    }
    
    var borderColor: Color {
        switch self {
        case .primary, .destructive, .selection:
            return .clear
        case .secondary:
            return Color(.separatorColor)
        case .ghost:
            return .accentColor.opacity(0.3)
        }
    }
    
    var borderWidth: CGFloat {
        switch self {
        case .primary, .destructive, .selection:
            return 0
        case .secondary, .ghost:
            return 1
        }
    }
}

enum NativeButtonSize {
    case small
    case medium
    case large
    
    var font: Font {
        switch self {
        case .small:
            return .caption
        case .medium:
            return .body
        case .large:
            return .title3
        }
    }
    
    var padding: EdgeInsets {
        switch self {
        case .small:
            return EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
        case .medium:
            return EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        case .large:
            return EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        }
    }
    
    var cornerRadius: CGFloat {
        switch self {
        case .small:
            return 6
        case .medium:
            return 8
        case .large:
            return 10
        }
    }
}

// MARK: - Native Toggle Style

struct NativeToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(configuration.isOn ? Color.accentColor : Color(.controlBackgroundColor))
                    .frame(width: 50, height: 30)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color(.separatorColor), lineWidth: 0.5)
                    )
                
                Circle()
                    .fill(.white)
                    .frame(width: 26, height: 26)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .offset(x: configuration.isOn ? 10 : -10)
                    .animation(AppleAnimationCurves.snappySpring, value: configuration.isOn)
            }
            .onTapGesture {
                NativeHapticFeedback.light()
                configuration.isOn.toggle()
            }
            .nativeHoverEffect(scaleEffect: 1.05)
        }
        .animation(AppleAnimationCurves.gentleSpring, value: configuration.isOn)
    }
}

// MARK: - Native Progress View

struct NativeProgressView: View {
    let value: Double
    let total: Double
    let style: NativeProgressStyle
    
    init(value: Double, total: Double = 1.0, style: NativeProgressStyle = .linear) {
        self.value = value
        self.total = total
        self.style = style
    }
    
    var body: some View {
        switch style {
        case .linear:
            LinearProgressView(value: value, total: total)
        case .circular:
            CircularProgressView(value: value, total: total)
        case .ring:
            RingProgressView(value: value, total: total)
        }
    }
}

enum NativeProgressStyle {
    case linear
    case circular
    case ring
}

struct LinearProgressView: View {
    let value: Double
    let total: Double
    
    @State private var animatedValue: Double = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.controlBackgroundColor))
                    .frame(height: 8)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [.accentColor, .accentColor.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * animatedValue / total, height: 8)
                    .animation(AppleAnimationCurves.gentleSpring, value: animatedValue)
            }
        }
        .frame(height: 8)
        .onAppear {
            withAnimation(AppleAnimationCurves.gentleSpring.delay(0.1)) {
                animatedValue = value
            }
        }
        .onChange(of: value) { _, newValue in
            withAnimation(AppleAnimationCurves.gentleSpring) {
                animatedValue = newValue
            }
        }
    }
}

struct CircularProgressView: View {
    let value: Double
    let total: Double
    
    @State private var animatedValue: Double = 0
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.controlBackgroundColor), lineWidth: 6)
            
            Circle()
                .trim(from: 0, to: animatedValue / total)
                .stroke(
                    AngularGradient(
                        colors: [.accentColor, .accentColor.opacity(0.6), .accentColor],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(AppleAnimationCurves.gentleSpring, value: animatedValue)
        }
        .onAppear {
            withAnimation(AppleAnimationCurves.gentleSpring.delay(0.1)) {
                animatedValue = value
            }
        }
        .onChange(of: value) { _, newValue in
            withAnimation(AppleAnimationCurves.gentleSpring) {
                animatedValue = newValue
            }
        }
    }
}

struct RingProgressView: View {
    let value: Double
    let total: Double
    
    @State private var animatedValue: Double = 0
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.controlBackgroundColor), lineWidth: 4)
            
            Circle()
                .trim(from: 0, to: animatedValue / total)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90 + rotation))
                .animation(AppleAnimationCurves.gentleSpring, value: animatedValue)
        }
        .onAppear {
            withAnimation(AppleAnimationCurves.gentleSpring.delay(0.1)) {
                animatedValue = value
            }
            
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
        .onChange(of: value) { _, newValue in
            withAnimation(AppleAnimationCurves.gentleSpring) {
                animatedValue = newValue
            }
        }
    }
}

// MARK: - Native Loading Indicators

struct NativeLoadingIndicator: View {
    let style: LoadingStyle
    let size: CGFloat
    
    init(style: LoadingStyle = .dots, size: CGFloat = 20) {
        self.style = style
        self.size = size
    }
    
    var body: some View {
        switch style {
        case .dots:
            DotsLoadingView(size: size)
        case .spinner:
            SpinnerLoadingView(size: size)
        case .pulse:
            PulseLoadingView(size: size)
        case .wave:
            WaveLoadingView(size: size)
        }
    }
}

enum LoadingStyle {
    case dots
    case spinner
    case pulse
    case wave
}

struct DotsLoadingView: View {
    let size: CGFloat
    
    @State private var animationPhase: CGFloat = 0
    
    var body: some View {
        HStack(spacing: size * 0.3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: size * 0.3, height: size * 0.3)
                    .scaleEffect(1 + 0.5 * sin(animationPhase + Double(index) * .pi / 3))
                    .opacity(0.6 + 0.4 * sin(animationPhase + Double(index) * .pi / 3))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                animationPhase = .pi * 2
            }
        }
    }
}

struct SpinnerLoadingView: View {
    let size: CGFloat
    
    @State private var rotation: Double = 0
    
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(
                AngularGradient(
                    colors: [.accentColor, .accentColor.opacity(0.3)],
                    center: .center
                ),
                style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

struct PulseLoadingView: View {
    let size: CGFloat
    
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0.6
    
    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: size, height: size)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    scale = 1.2
                    opacity = 0.3
                }
            }
    }
}

struct WaveLoadingView: View {
    let size: CGFloat
    
    @State private var animationPhase: CGFloat = 0
    
    var body: some View {
        HStack(spacing: size * 0.1) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: size * 0.05)
                    .fill(Color.accentColor)
                    .frame(width: size * 0.12, height: size * 0.6)
                    .scaleEffect(y: 0.4 + 0.6 * abs(sin(animationPhase + Double(index) * .pi / 4)))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                animationPhase = .pi * 2
            }
        }
    }
}

// MARK: - Native Card Views

struct NativeCard<Content: View>: View {
    let content: Content
    let style: CardStyle
    
    init(style: CardStyle = .elevated, @ViewBuilder content: () -> Content) {
        self.style = style
        self.content = content()
    }
    
    var body: some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(style.backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(style.borderColor, lineWidth: style.borderWidth)
                    )
            )
            .shadow(
                color: style.shadowColor,
                radius: style.shadowRadius,
                x: 0,
                y: style.shadowOffset
            )
            .nativeCardStyle()
    }
}

enum CardStyle {
    case flat
    case elevated
    case outlined
    case glass
    
    var backgroundColor: Color {
        switch self {
        case .flat:
            return Color(.controlBackgroundColor)
        case .elevated:
            return Color(.controlBackgroundColor)
        case .outlined:
            return .clear
        case .glass:
            return .clear
        }
    }
    
    var borderColor: Color {
        switch self {
        case .flat, .elevated:
            return .clear
        case .outlined:
            return Color(.separatorColor)
        case .glass:
            return .white.opacity(0.2)
        }
    }
    
    var borderWidth: CGFloat {
        switch self {
        case .flat, .elevated:
            return 0
        case .outlined, .glass:
            return 1
        }
    }
    
    var shadowColor: Color {
        switch self {
        case .flat, .outlined:
            return .clear
        case .elevated:
            return .black.opacity(0.1)
        case .glass:
            return .black.opacity(0.05)
        }
    }
    
    var shadowRadius: CGFloat {
        switch self {
        case .flat, .outlined:
            return 0
        case .elevated:
            return 8
        case .glass:
            return 4
        }
    }
    
    var shadowOffset: CGFloat {
        switch self {
        case .flat, .outlined, .glass:
            return 0
        case .elevated:
            return 2
        }
    }
}

// MARK: - Native Notification View

struct NativeNotification: View {
    let title: String
    let message: String
    let type: NotificationType
    let action: (() -> Void)?
    
    @State private var isVisible: Bool = false
    @State private var offset: CGFloat = -100
    
    init(title: String, message: String, type: NotificationType = .info, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.type = type
        self.action = action
    }
    
    var body: some View {
        HStack {
            Image(systemName: type.iconName)
                .foregroundColor(type.color)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            if let action = action {
                Button("Action") {
                    action()
                }
                .buttonStyle(NativeButtonStyle(style: .ghost, size: .small))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        )
        .offset(y: offset)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.9)
        .animation(AppleAnimationCurves.notification, value: isVisible)
        .animation(AppleAnimationCurves.notification, value: offset)
        .onAppear {
            show()
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.y < -50 {
                        hide()
                    }
                }
        )
    }
    
    func show() {
        withAnimation(AppleAnimationCurves.notification) {
            isVisible = true
            offset = 0
        }
    }
    
    func hide() {
        withAnimation(AppleAnimationCurves.dismissal) {
            isVisible = false
            offset = -100
        }
    }
}

enum NotificationType {
    case info
    case success
    case warning
    case error
    
    var iconName: String {
        switch self {
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .info:
            return .blue
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}

// MARK: - Native Menu Views

struct NativeContextMenu<Content: View>: View {
    let content: Content
    let menuItems: [NativeMenuItem]
    
    init(menuItems: [NativeMenuItem], @ViewBuilder content: () -> Content) {
        self.content = content()
        self.menuItems = menuItems
    }
    
    var body: some View {
        content
            .contextMenu {
                ForEach(menuItems, id: \.id) { item in
                    Button(action: item.action) {
                        Label(item.title, systemImage: item.iconName)
                    }
                    .keyboardShortcut(item.keyboardShortcut ?? KeyEquivalent(""))
                }
            }
    }
}

struct NativeMenuItem {
    let id = UUID()
    let title: String
    let iconName: String
    let action: () -> Void
    let keyboardShortcut: KeyEquivalent?
    
    init(title: String, iconName: String, keyboardShortcut: KeyEquivalent? = nil, action: @escaping () -> Void) {
        self.title = title
        self.iconName = iconName
        self.keyboardShortcut = keyboardShortcut
        self.action = action
    }
}

// MARK: - View Extensions for Native Components

extension View {
    func nativeButtonStyle(_ style: NativeButtonStyleType = .primary, size: NativeButtonSize = .medium) -> some View {
        self.buttonStyle(NativeButtonStyle(style: style, size: size))
    }
    
    func nativeToggleStyle() -> some View {
        self.toggleStyle(NativeToggleStyle())
    }
    
    func nativeCard(_ style: CardStyle = .elevated) -> some View {
        NativeCard(style: style) {
            self
        }
    }
    
    func nativeContextMenu(_ items: [NativeMenuItem]) -> some View {
        NativeContextMenu(menuItems: items) {
            self
        }
    }
}

// MARK: - Native Status Indicators

struct NativeStatusIndicator: View {
    let status: StatusType
    let size: CGFloat
    
    init(status: StatusType, size: CGFloat = 12) {
        self.status = status
        self.size = size
    }
    
    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(.white, lineWidth: size * 0.1)
            )
            .shadow(color: status.color.opacity(0.5), radius: size * 0.2)
            .pulse(minOpacity: 0.8, maxOpacity: 1.0, duration: 2.0)
    }
}

enum StatusType {
    case online
    case offline
    case away
    case busy
    case error
    
    var color: Color {
        switch self {
        case .online:
            return .green
        case .offline:
            return .gray
        case .away:
            return .yellow
        case .busy:
            return .red
        case .error:
            return .red
        }
    }
}

// MARK: - Native Tooltip

struct NativeTooltip: ViewModifier {
    let text: String
    @State private var showTooltip = false
    
    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                withAnimation(AppleAnimationCurves.hoverResponse.delay(hovering ? 0.5 : 0)) {
                    showTooltip = hovering
                }
            }
            .overlay(
                Group {
                    if showTooltip {
                        Text(text)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.regularMaterial)
                                    .shadow(radius: 4)
                            )
                            .offset(y: -30)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.8).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                },
                alignment: .top
            )
    }
}

extension View {
    func nativeTooltip(_ text: String) -> some View {
        modifier(NativeTooltip(text: text))
    }
}