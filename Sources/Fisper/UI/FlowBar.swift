import SwiftUI
import AppKit
import Combine

/// Shared state between the AppKit panel and the SwiftUI pill.
@MainActor
final class FlowBarModel: ObservableObject {
    @Published var hovering = false
    @Published var nearby = false
    @Published var dragging = false
    @Published var anchorTop = false
    var pillFrame: CGRect = .zero          // in the panel's SwiftUI coordinates (top-left origin)
    var onDragChanged: () -> Void = {}
    var onDragEnded: () -> Void = {}
    var onMove: (BarPosition) -> Void = { _ in }
}

private final class FlowPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click on the pill work even when Fisper isn't the active app.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The floating pill. One capsule that morphs between states; drag it anywhere, it remembers where.
@MainActor
final class FlowBarController {
    private let panel: NSPanel
    private let state = AppState.shared
    private var prefs: Preferences { state.prefs }
    private var bag = Set<AnyCancellable>()
    private let model = FlowBarModel()
    static let panelSize = NSSize(width: 440, height: 120)
    private var dragStartMouse: NSPoint = .zero
    private var dragStartOrigin: NSPoint = .zero
    private var lastScreen: NSScreen?

    init() {
        panel = FlowPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.ignoresMouseEvents = true      // flipped on only while the pointer is over the pill
        let host = FirstMouseHostingView(rootView: FlowBarView(model: model).environmentObject(state).environmentObject(state.prefs))
        host.sizingOptions = []
        panel.contentView = host

        model.onDragChanged = { [weak self] in self?.dragChanged() }
        model.onDragEnded = { [weak self] in self?.dragEnded() }
        model.onMove = { [weak self] pos in
            guard let self else { return }
            self.prefs.barCustomPosition = nil
            self.prefs.barPosition = pos
            self.reposition(force: true)
        }

        state.$phase.sink { [weak self] p in self?.update(phase: p) }.store(in: &bag)
        prefs.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { guard let self else { return }; self.reposition(); self.update(phase: self.state.phase) }
        }.store(in: &bag)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition(force: true) }
        }
        // Pointer tracking works even when Fisper is in the background (no permissions needed).
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackMouse() }
        }
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
        reposition(force: true)
        update(phase: .idle)
    }

    // MARK: Position

    private var currentScreen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    func reposition(force: Bool = false) {
        guard !model.dragging else { return }
        if case .recording = state.phase, panel.isVisible, !force { return }   // don't jump screens mid-dictation
        guard let screen = currentScreen else { return }
        if !force && screen == lastScreen && panel.isVisible && prefs.barCustomPosition == nil && !needsPresetMove(screen) { return }
        lastScreen = screen
        let vf = screen.visibleFrame
        let size = panel.frame.size
        var origin: NSPoint
        if let p = prefs.barCustomPosition {
            origin = NSPoint(x: vf.minX + p.x * vf.width - size.width / 2, y: vf.minY + p.y * vf.height - size.height / 2)
            model.anchorTop = p.y > 0.5
        } else {
            let top = prefs.barPosition == .top
            origin = NSPoint(x: vf.midX - size.width / 2, y: top ? vf.maxY - size.height : vf.minY)
            model.anchorTop = top
        }
        origin = clamp(origin, in: vf)
        origin = NSPoint(x: origin.x.rounded(), y: origin.y.rounded())
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
    }

    private func needsPresetMove(_ screen: NSScreen) -> Bool {
        let vf = screen.visibleFrame
        let size = panel.frame.size
        let top = prefs.barPosition == .top
        let want = NSPoint(x: (vf.midX - size.width / 2).rounded(), y: (top ? vf.maxY - size.height : vf.minY).rounded())
        return panel.frame.origin != want
    }

    private func clamp(_ o: NSPoint, in vf: NSRect) -> NSPoint {
        let s = panel.frame.size
        // keep the pill (centered in the panel) at least 40 pt inside the screen edges
        return NSPoint(x: min(max(o.x, vf.minX + 40 - s.width / 2), vf.maxX - 40 - s.width / 2),
                       y: min(max(o.y, vf.minY), vf.maxY - s.height))
    }

    // MARK: Drag

    private func dragChanged() {
        if !model.dragging {
            model.dragging = true
            dragStartMouse = NSEvent.mouseLocation
            dragStartOrigin = panel.frame.origin
            NSCursor.closedHand.push()
        }
        let m = NSEvent.mouseLocation
        var o = NSPoint(x: dragStartOrigin.x + m.x - dragStartMouse.x, y: dragStartOrigin.y + m.y - dragStartMouse.y)
        if let vf = (NSScreen.screens.first { NSMouseInRect(m, $0.frame, false) } ?? NSScreen.main)?.visibleFrame {
            // gentle snap to the horizontal center
            if abs((o.x + panel.frame.width / 2) - vf.midX) < 14 { o.x = vf.midX - panel.frame.width / 2 }
            o = clamp(o, in: vf)
        }
        panel.setFrameOrigin(o)
        if let vf = currentScreen?.visibleFrame { model.anchorTop = (o.y + panel.frame.height / 2 - vf.minY) / vf.height > 0.5 }
    }

    private func dragEnded() {
        NSCursor.pop()
        model.dragging = false
        guard let screen = (NSScreen.screens.first { $0.frame.intersects(panel.frame) } ?? NSScreen.main) else { return }
        let vf = screen.visibleFrame
        let c = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let fx = (c.x - vf.minX) / vf.width, fy = (c.y - vf.minY) / vf.height
        // dropped back on a preset spot → use the preset
        if abs(fx - 0.5) < 0.02 && panel.frame.minY - vf.minY < 6 { prefs.barCustomPosition = nil; prefs.barPosition = .bottom }
        else if abs(fx - 0.5) < 0.02 && vf.maxY - panel.frame.maxY < 6 { prefs.barCustomPosition = nil; prefs.barPosition = .top }
        else { prefs.barCustomPosition = CGPoint(x: min(1, max(0, fx)), y: min(1, max(0, fy))) }
        lastScreen = screen
    }

    // MARK: Hover

    private func trackMouse() {
        guard panel.isVisible else { return }
        if model.dragging { panel.ignoresMouseEvents = false; return }
        let f = model.pillFrame
        guard f.width > 0 else { return }
        let screenRect = NSRect(x: panel.frame.minX + f.minX, y: panel.frame.maxY - f.maxY, width: f.width, height: f.height)
        let mouse = NSEvent.mouseLocation
        let near = screenRect.insetBy(dx: -90, dy: -60).contains(mouse)
        if model.nearby != near { withAnimation(.easeOut(duration: 0.2)) { model.nearby = near } }
        // in "near pointer" mode the idle pill is invisible until you approach — don't eat clicks before that
        let pillShown = state.phase != .idle || prefs.idleBar == .always || (prefs.idleBar == .nearby && near)
        let inside = pillShown && screenRect.insetBy(dx: -8, dy: -8).contains(mouse)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        if model.hovering != inside {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { model.hovering = inside }
        }
    }

    private func update(phase: AppState.Phase) {
        let visible: Bool
        switch phase {
        case .idle: visible = prefs.showIdleBar
        default: visible = true
        }
        if visible {
            if !panel.isVisible { reposition(force: true); panel.orderFrontRegardless() }
        } else if panel.isVisible {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, case .idle = self.state.phase, !self.prefs.showIdleBar else { return }
                self.panel.orderOut(nil)
            }
        }
    }
}

struct FlowBarView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: Preferences
    @ObservedObject var model: FlowBarModel

    var body: some View {
        let top = model.anchorTop
        ZStack(alignment: top ? .top : .bottom) {
            Color.clear
            FlowPill(phase: state.phase, levels: state.levels, hovering: model.hovering || model.dragging,
                     keyLabel: prefs.hotkey.keyLabel, style: prefs.barStyle,
                     barColor: prefs.barColor.color, waveColor: prefs.waveColor.color, opacity: prefs.barOpacity,
                     hidden: state.phase == .idle && (prefs.idleBar == .dictating || (prefs.idleBar == .nearby && !model.nearby && !model.hovering)),
                     onTap: { state.toggleHandsFree() },
                     onCancel: { state.cancel(silent: false) },
                     onDone: { state.stopAndTranscribe(reason: "button") })
                .scaleEffect(prefs.barScale, anchor: top ? .top : .bottom)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.pillFrame = $0 }
                .gesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .global)
                        .onChanged { _ in model.onDragChanged() }
                        .onEnded { _ in model.onDragEnded() }
                )
                .contextMenu {
                    Button(isRecording ? "Finish dictation" : "Start dictation") { state.toggleHandsFree() }
                    Divider()
                    Button("Move to bottom center") { model.onMove(.bottom) }
                    Button("Move to top center") { model.onMove(.top) }
                    Picker("Show the bar", selection: Binding(get: { prefs.idleBar }, set: { prefs.idleBar = $0 })) {
                        ForEach(IdleBarMode.allCases) { Text($0.title).tag($0) }
                    }
                    Divider()
                    Button("Flow bar settings…") {
                        state.selectedPage = .appearance
                        NotificationCenter.default.post(name: .fisperOpenWindow, object: nil)
                    }
                }
                .padding(top ? .top : .bottom, 10)
        }
        .frame(width: FlowBarController.panelSize.width, height: FlowBarController.panelSize.height)
    }

    private var isRecording: Bool { if case .recording = state.phase { return true }; return false }
}

struct FlowPill: View {
    let phase: AppState.Phase
    let levels: [Float]
    let hovering: Bool
    let keyLabel: String
    let style: BarStyle
    var barColor: Color = Color(hex: 0x0B0B0C)
    var waveColor: Color = .white
    var opacity: Double = 0.82
    var hidden = false
    var onTap: () -> Void = {}
    var onCancel: () -> Void = {}
    var onDone: () -> Void = {}

    private enum Kind: Equatable { case idle, hover, listening, handsFree, thinking, notice }
    private var kind: Kind {
        switch phase {
        case .idle: return hovering ? .hover : .idle
        case .recording(let hf): return hf ? .handsFree : .listening
        case .processing: return .thinking
        case .notice: return .notice
        }
    }

    private var size: CGSize {
        switch kind {
        case .idle: return CGSize(width: 58, height: 18)
        case .hover: return CGSize(width: 0, height: 34)
        case .listening: return CGSize(width: 112, height: 36)
        case .handsFree: return CGSize(width: 176, height: 38)
        case .thinking: return CGSize(width: 112, height: 36)
        case .notice: return CGSize(width: 0, height: 34)
        }
    }

    var body: some View {
        content
            .frame(width: size.width == 0 ? nil : size.width, height: size.height)
            .padding(.horizontal, size.width == 0 ? 16 : 0)
            .background { background }
            .overlay { Capsule().strokeBorder(.white.opacity(borderOpacity), lineWidth: kind == .idle ? 1 : 1.25) }
            .compositingGroup()
            .shadow(color: .black.opacity(0.32), radius: kind == .idle ? 5 : 14, y: kind == .idle ? 2 : 5)
            .opacity(hidden ? 0 : 1)
            .scaleEffect(hidden ? 0.6 : 1)
            .contentShape(Capsule())
            .onTapGesture { if kind == .idle || kind == .hover { onTap() } }
            .animation(.spring(response: 0.36, dampingFraction: 0.78), value: kind)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: hidden)
            .help("Click to dictate · drag to move · right-click for options")
    }

    private var borderOpacity: Double {
        switch kind {
        case .idle: return 0.55
        case .hover: return 0.6
        case .listening, .handsFree: return style == .midnight ? 0.9 : 0.6
        default: return 0.35
        }
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .glass:
            // The solid base is a separate layer *under* the glass, so the pill is always clearly visible —
            // even where Liquid Glass can't sample the background. The glass only adds the sheen.
            // (SwiftUI's .glassEffect doesn't draw reliably in a floating non-activating panel, so the glass
            //  look is built from a blur material, a tinted body and a specular highlight.)
            ZStack {
                Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                Capsule().fill(barColor.opacity(max(0.5, opacity * (kind == .idle ? 0.8 : 0.92))))
                Capsule().fill(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04), .clear],
                                              startPoint: .top, endPoint: .center))
                    .padding(1)
            }
        case .midnight:
            Capsule().fill(barColor.opacity(kind == .idle ? max(0.6, opacity) : 1))
        }
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .idle:
            HStack(spacing: 2.5) {
                ForEach([0.35, 0.6, 1.0, 0.6, 0.35], id: \.self) { h in
                    Capsule().fill(waveColor.opacity(0.85)).frame(width: 2.2, height: 9 * h)
                }
            }
            .transition(.opacity)
        case .hover:
            HStack(spacing: 6) {
                Image(systemName: "mic.fill").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(waveColor)
                Text("Click or hold").foregroundStyle(waveColor.opacity(0.75))
                Text(keyLabel).fontWeight(.semibold).foregroundStyle(waveColor)
                Text("to dictate").foregroundStyle(waveColor.opacity(0.75))
                Image(systemName: "line.3.horizontal").font(.system(size: 9.5)).foregroundStyle(waveColor.opacity(0.45))
            }
            .font(.system(size: 12, weight: .medium))
            .fixedSize()
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
        case .listening:
            WaveformBars(levels: levels, color: waveColor).frame(height: 20).transition(.opacity)
        case .handsFree:
            HStack(spacing: 8) {
                CircleButton(symbol: "xmark", tint: waveColor, action: onCancel)
                WaveformBars(levels: levels, count: 11, color: waveColor).frame(height: 20)
                CircleButton(symbol: "checkmark", filled: true, tint: waveColor, ink: barColor, action: onDone)
            }
            .transition(.opacity)
        case .thinking:
            ThinkingDots(color: waveColor).transition(.opacity)
        case .notice:
            if case .notice(let msg, let isError) = phase {
                HStack(spacing: 7) {
                    Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(isError ? Color(hex: 0xFF9F8A) : Color(hex: 0x7FE0C4))
                    Text(msg).foregroundStyle(waveColor).lineLimit(1)
                }
                .font(.system(size: 12.5, weight: .medium))
                .fixedSize()
                .transition(.opacity)
            }
        }
    }
}

struct WaveformBars: View {
    let levels: [Float]
    var count = 13
    var color: Color = .white
    var body: some View {
        HStack(spacing: 2.6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(color).frame(width: 2.6, height: 3 + CGFloat(sample(i)) * 15)
            }
        }
        .animation(.easeOut(duration: 0.08), value: levels)
    }
    /// Symmetric "voice" shape: newest audio in the middle, older toward the edges.
    private func sample(_ i: Int) -> Float {
        let mid = count / 2
        let dist = abs(i - mid)
        let idx = max(0, levels.count - 1 - dist * 2)
        let base = levels.isEmpty ? 0 : levels[idx]
        let shape: Float = 1 - Float(dist) / Float(mid + 2) * 0.55
        return min(1, base * shape * 1.25)
    }
}

struct CircleButton: View {
    let symbol: String
    var filled = false
    var tint: Color = .white
    var ink: Color = Color(hex: 0x0B0B0C)
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(filled ? ink : tint)
                .frame(width: 25, height: 25)
                .background(Circle().fill(filled ? tint.opacity(hover ? 1 : 0.9) : tint.opacity(hover ? 0.32 : 0.18)))
                .scaleEffect(hover ? 1.08 : 1)
                .animation(.spring(response: 0.25), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct ThinkingDots: View {
    var color: Color = .white
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<9, id: \.self) { i in
                    let y = (sin(t * 7 - Double(i) * 0.6) + 1) / 2
                    Capsule().fill(color.opacity(0.35 + 0.65 * y)).frame(width: 2.6, height: 3 + CGFloat(y) * 6)
                }
            }
        }
    }
}
