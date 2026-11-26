import SwiftUI
import AppKit
import Combine

/// The floating pill. One capsule that morphs between states (idle → listening → hands-free → thinking → notice).
@MainActor
final class FlowBarController {
    private let panel: NSPanel
    private let state = AppState.shared
    private var bag = Set<AnyCancellable>()
    private let hover = FlowBarHover()
    static let panelSize = NSSize(width: 420, height: 110)

    init() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        // ignoresMouseEvents is deliberately left unset: AppKit then passes clicks through transparent pixels,
        // so only the pill itself is clickable.
        let host = NSHostingView(rootView: FlowBarView(hover: hover).environmentObject(state).environmentObject(state.prefs))
        host.sizingOptions = []
        panel.contentView = host

        state.$phase.sink { [weak self] p in self?.update(phase: p) }.store(in: &bag)
        state.prefs.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { guard let self else { return }; self.reposition(); self.update(phase: self.state.phase) }
        }.store(in: &bag)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
        reposition()
        update(phase: .idle)
    }

    private var currentScreen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    func reposition() {
        // don't jump screens mid-dictation
        if case .recording = state.phase, panel.isVisible { return }
        guard let screen = currentScreen else { return }
        let vf = screen.visibleFrame
        let size = panel.frame.size
        let y = state.prefs.barPosition == .bottom ? vf.minY + 4 : vf.maxY - size.height - 4
        let origin = NSPoint(x: (vf.midX - size.width / 2).rounded(), y: y.rounded())
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
    }

    private func update(phase: AppState.Phase) {
        let visible: Bool
        switch phase {
        case .idle: visible = state.prefs.showIdleBar
        default: visible = true
        }
        if visible {
            if !panel.isVisible { reposition(); panel.orderFrontRegardless() }
        } else if panel.isVisible {
            // let the collapse animation finish before hiding
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, case .idle = self.state.phase, !self.state.prefs.showIdleBar else { return }
                self.panel.orderOut(nil)
            }
        }
    }
}

final class FlowBarHover: ObservableObject { @Published var hovering = false }

struct FlowBarView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: Preferences
    @ObservedObject var hover: FlowBarHover

    var body: some View {
        let bottom = prefs.barPosition == .bottom
        ZStack(alignment: bottom ? .bottom : .top) {
            Color.clear
            FlowPill(phase: state.phase, levels: state.levels, hovering: hover.hovering, keyLabel: prefs.hotkey.keyLabel,
                     style: prefs.barStyle, hidden: !prefs.showIdleBar && state.phase == .idle,
                     onTap: { state.toggleHandsFree() },
                     onCancel: { state.cancel(silent: false) },
                     onDone: { state.stopAndTranscribe(reason: "button") },
                     onHover: { h in withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { hover.hovering = h } })
                .scaleEffect(prefs.barScale, anchor: bottom ? .bottom : .top)
                .padding(bottom ? .bottom : .top, 8)
        }
        .frame(width: FlowBarController.panelSize.width, height: FlowBarController.panelSize.height)
    }
}

private let midnight = Color(hex: 0x0B0B0C)

struct FlowPill: View {
    let phase: AppState.Phase
    let levels: [Float]
    let hovering: Bool
    let keyLabel: String
    let style: BarStyle
    var hidden = false
    var onTap: () -> Void = {}
    var onCancel: () -> Void = {}
    var onDone: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }

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
        case .idle: return CGSize(width: 46, height: 10)
        case .hover: return CGSize(width: 212, height: 30)
        case .listening: return CGSize(width: 108, height: 34)
        case .handsFree: return CGSize(width: 172, height: 36)
        case .thinking: return CGSize(width: 108, height: 34)
        case .notice: return CGSize(width: 0, height: 32)
        }
    }

    var body: some View {
        content
            .frame(width: kind == .notice ? nil : size.width, height: size.height)
            .padding(.horizontal, kind == .notice ? 14 : 0)
            .background { background }
            .overlay {
                Capsule().strokeBorder(borderColor, lineWidth: kind == .idle ? 0.75 : 1)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(kind == .idle ? 0.12 : 0.28), radius: kind == .idle ? 3 : 12, y: kind == .idle ? 1 : 4)
            .opacity(hidden ? 0 : 1)
            .scaleEffect(hidden ? 0.6 : 1)
            .contentShape(Capsule())
            .onHover(perform: onHover)
            .onTapGesture { if kind == .idle || kind == .hover { onTap() } }
            .animation(.spring(response: 0.36, dampingFraction: 0.78), value: kind)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: hidden)
    }

    private var borderColor: Color {
        switch kind {
        case .idle: return .white.opacity(0.35)
        case .listening, .handsFree: return .white.opacity(style == .midnight ? 0.9 : 0.45)
        default: return .white.opacity(0.25)
        }
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .glass:
            // a dark wash under the glass keeps white content readable on any wallpaper
            Capsule().fill(Color.black.opacity(kind == .idle ? 0.35 : 0.5))
                .glassEffect(.regular.tint(Color.black.opacity(0.25)), in: Capsule())
        case .midnight:
            Capsule().fill(midnight.opacity(kind == .idle ? 0.6 : 1))
        }
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .idle:
            HStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { _ in Circle().fill(Color.white.opacity(0.55)).frame(width: 2, height: 2) }
            }
            .transition(.opacity)
        case .hover:
            HStack(spacing: 5) {
                Text("Click or hold").foregroundStyle(.white.opacity(0.75))
                Text(keyLabel).fontWeight(.semibold).foregroundStyle(.white)
                Text("to dictate").foregroundStyle(.white.opacity(0.75))
            }
            .font(.system(size: 11.5, weight: .medium))
            .fixedSize()
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        case .listening:
            WaveformBars(levels: levels).frame(height: 20).transition(.opacity)
        case .handsFree:
            HStack(spacing: 8) {
                CircleButton(symbol: "xmark", action: onCancel)
                WaveformBars(levels: levels, count: 11).frame(height: 20)
                CircleButton(symbol: "checkmark", filled: true, action: onDone)
            }
            .transition(.opacity)
        case .thinking:
            ThinkingDots().transition(.opacity)
        case .notice:
            if case .notice(let msg, let isError) = phase {
                HStack(spacing: 7) {
                    Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(isError ? Color(hex: 0xFF9F8A) : Color(hex: 0x7FE0C4))
                    Text(msg).foregroundStyle(.white).lineLimit(1)
                }
                .font(.system(size: 12, weight: .medium))
                .fixedSize()
                .transition(.opacity)
            }
        }
    }
}

struct WaveformBars: View {
    let levels: [Float]
    var count = 13
    var body: some View {
        HStack(spacing: 2.6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(Color.white)
                    .frame(width: 2.6, height: 3 + CGFloat(sample(i)) * 15)
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
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(filled ? midnight : .white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(filled ? Color.white.opacity(hover ? 1 : 0.9) : Color.white.opacity(hover ? 0.32 : 0.18)))
                .scaleEffect(hover ? 1.06 : 1)
                .animation(.spring(response: 0.25), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct ThinkingDots: View {
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<9, id: \.self) { i in
                    let y = (sin(t * 7 - Double(i) * 0.6) + 1) / 2
                    Capsule().fill(Color.white.opacity(0.35 + 0.65 * y))
                        .frame(width: 2.6, height: 3 + CGFloat(y) * 6)
                }
            }
        }
    }
}
