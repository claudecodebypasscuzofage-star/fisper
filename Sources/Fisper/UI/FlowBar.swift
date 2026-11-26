import SwiftUI
import AppKit
import Combine

/// The floating pill at the bottom of the screen. Tiny when idle, shows a live waveform while you talk.
@MainActor
final class FlowBarController {
    private let panel: NSPanel
    private let state = AppState.shared
    private var bag = Set<AnyCancellable>()
    private let hover = FlowBarHover()

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 64),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        let host = NSHostingView(rootView: FlowBarView(hover: hover).environmentObject(state).environmentObject(state.prefs))
        host.sizingOptions = []
        panel.contentView = host

        state.$phase.sink { [weak self] p in self?.update(phase: p) }.store(in: &bag)
        state.prefs.$showIdleBar.sink { [weak self] _ in
            DispatchQueue.main.async { self?.update(phase: self?.state.phase ?? .idle) }
        }.store(in: &bag)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
        // follow the user's active screen
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
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
        guard let screen = currentScreen else { return }
        let vf = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(x: vf.midX - size.width / 2, y: vf.minY + 6)
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
    }

    private func update(phase: AppState.Phase) {
        let visible: Bool
        switch phase {
        case .idle: visible = state.prefs.showIdleBar
        default: visible = true
        }
        // ignoresMouseEvents is deliberately left unset: AppKit then passes clicks through the panel's transparent pixels,
        // so only the pill itself is clickable.
        if visible {
            reposition()
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else {
            panel.orderOut(nil)
        }
    }
}

final class FlowBarHover: ObservableObject { @Published var hovering = false }

struct FlowBarView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: Preferences
    @ObservedObject var hover: FlowBarHover

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            pill
                .padding(.bottom, 6)
        }
        .frame(width: 320, height: 64)
    }

    @ViewBuilder private var pill: some View {
        switch state.phase {
        case .idle:
            IdlePill(hovering: hover.hovering, keyLabel: prefs.hotkey.keyLabel)
                .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { hover.hovering = h } }
                .onTapGesture { state.toggleHandsFree() }
        case .recording(let handsFree):
            RecordingPill(levels: state.levels, handsFree: handsFree,
                          onCancel: { state.cancel(silent: false) },
                          onDone: { state.stopAndTranscribe(reason: "button") })
        case .processing:
            ProcessingPill()
        case .notice(let msg, let isError):
            NoticePill(message: msg, isError: isError)
        }
    }
}

private let pillBlack = Color(hex: 0x0D0D0D)

struct IdlePill: View {
    let hovering: Bool
    let keyLabel: String
    var body: some View {
        ZStack {
            Capsule().fill(pillBlack.opacity(hovering ? 0.92 : 0.55))
            Capsule().strokeBorder(Color.white.opacity(hovering ? 0.35 : 0.28), lineWidth: 1)
            if hovering {
                HStack(spacing: 6) {
                    Text("Click or hold").foregroundStyle(.white.opacity(0.75))
                    Text(keyLabel).fontWeight(.semibold).foregroundStyle(.white)
                    Text("to dictate").foregroundStyle(.white.opacity(0.75))
                }
                .font(.system(size: 11.5))
                .transition(.opacity)
            } else {
                HStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { _ in Circle().fill(Color.white.opacity(0.45)).frame(width: 2, height: 2) }
                }
            }
        }
        .frame(width: hovering ? 210 : 46, height: hovering ? 28 : 10)
        .contentShape(Capsule())
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: hovering)
    }
}

struct WaveformBars: View {
    let levels: [Float]
    var count = 13
    var body: some View {
        HStack(spacing: 2.6) {
            ForEach(0..<count, id: \.self) { i in
                let v = sample(i)
                Capsule()
                    .fill(Color.white)
                    .frame(width: 2.6, height: 3 + CGFloat(v) * 15)
            }
        }
        .animation(.easeOut(duration: 0.09), value: levels)
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

struct RecordingPill: View {
    let levels: [Float]
    let handsFree: Bool
    let onCancel: () -> Void
    let onDone: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            if handsFree {
                CircleButton(symbol: "xmark", action: onCancel)
            }
            WaveformBars(levels: levels)
                .frame(height: 20)
            if handsFree {
                CircleButton(symbol: "checkmark", filled: true, action: onDone)
            }
        }
        .padding(.horizontal, handsFree ? 6 : 14)
        .frame(height: 34)
        .background(Capsule().fill(pillBlack))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
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
                .foregroundStyle(filled ? pillBlack : .white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(filled ? Color.white.opacity(hover ? 1 : 0.88) : Color.white.opacity(hover ? 0.32 : 0.2)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct ProcessingPill: View {
    @State private var phase: CGFloat = 0
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<9, id: \.self) { i in
                    let y = (sin(t * 7 - Double(i) * 0.6) + 1) / 2
                    Capsule().fill(Color.white.opacity(0.35 + 0.65 * y))
                        .frame(width: 2.6, height: 3 + CGFloat(y) * 5)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(Capsule().fill(pillBlack))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }
}

struct NoticePill: View {
    let message: String
    let isError: Bool
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? Color(hex: 0xFF9F8A) : Color(hex: 0x7FE0C4))
            Text(message).foregroundStyle(.white).lineLimit(1)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(Capsule().fill(pillBlack))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        .transition(.opacity)
    }
}
