import AppKit
import SwiftUI

class FloatingSubtitleWindow: NSPanel {
    private static let frameKey = "floatingWindowFrame"

    init(viewModel: TranslatorViewModel) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 72),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled, .closable],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        isMovableByWindowBackground = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        hasShadow = true
        isOpaque = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Frosted glass background
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true

        // SwiftUI content
        let subtitleView = FloatingSubtitleView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: subtitleView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        visualEffect.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
        ])

        contentView = visualEffect

        // Restore or default to bottom-right corner
        if let savedFrame = UserDefaults.standard.string(forKey: Self.frameKey) {
            let frame = NSRectFromString(savedFrame)
            if frame != .zero {
                setFrame(frame, display: false)
            } else {
                positionAtBottomRight()
            }
        } else {
            positionAtBottomRight()
        }
    }

    private func positionAtBottomRight() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.maxX - frame.width - 20
        let y = screenFrame.minY + 20
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: Self.frameKey)
    }

    func show() {
        orderFront(nil)
    }

    func hide() {
        orderOut(nil)
    }
}

struct FloatingSubtitleView: View {
    @ObservedObject var viewModel: TranslatorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !viewModel.currentLine.originalText.isEmpty {
                Text(viewModel.currentLine.originalText)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(2)
            }
            if !viewModel.currentLine.translatedText.isEmpty {
                Text(viewModel.currentLine.translatedText)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
            }
            if viewModel.currentLine.originalText.isEmpty && viewModel.currentLine.translatedText.isEmpty {
                Text("等待翻譯...")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 300, maxWidth: 600, alignment: .leading)
    }
}
