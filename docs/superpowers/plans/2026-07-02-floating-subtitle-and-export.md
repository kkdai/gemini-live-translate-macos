# Floating Subtitle Window + Meeting Transcript Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an always-on-top floating subtitle overlay and auto-save a bilingual Markdown transcript to Desktop when a translation session ends.

**Architecture:** The floating panel is an `NSPanel` holding a SwiftUI view via `NSHostingView`, bound to the existing `TranslatorViewModel`. The transcript export is a self-contained method on `TranslatorViewModel` called from `stop()`. Both features share the existing ViewModel with no new data layer.

**Tech Stack:** Swift 5, SwiftUI, AppKit (NSPanel, NSVisualEffectView, NSHostingView), Foundation (FileManager, DateFormatter)

## Global Constraints

- macOS 13.0 minimum (`LSMinimumSystemVersion` in Info.plist)
- Build command: `bash build_app.sh` from project root — must exit 0 with no new errors
- No Xcode project; compiled with `swiftc` via `build_app.sh` — all new `.swift` files must be added to the compile list in `build_app.sh`
- No third-party dependencies

---

### Task 1: Meeting Transcript Auto-Export

**Files:**
- Modify: `ContentView.swift`

**Interfaces:**
- Consumes: `TranslatorViewModel.subtitleHistory: [SubtitleLine]`, `TranslatorViewModel.stop()`
- Produces: `TranslatorViewModel.exportTranscript()` (private), file written to `~/Desktop/meeting-YYYY-MM-DD-HH-mm.md`

- [ ] **Step 1: Remove the 25-line history cap**

In `ContentView.swift`, find `checkAndRotateSubtitle` and delete the cap block:

```swift
// DELETE these three lines:
if self.subtitleHistory.count > 25 {
    self.subtitleHistory.removeFirst()
}
```

- [ ] **Step 2: Add `exportTranscript()` to `TranslatorViewModel`**

Add this method inside `TranslatorViewModel`, after the `stop()` method:

```swift
private func exportTranscript() {
    guard !subtitleHistory.isEmpty else { return }

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HH-mm"
    let timestamp = formatter.string(from: Date())
    let filename = "meeting-\(timestamp).md"

    let desktopURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop")
        .appendingPathComponent(filename)

    let displayFormatter = DateFormatter()
    displayFormatter.dateFormat = "yyyy-MM-dd HH:mm"
    let displayDate = displayFormatter.string(from: Date())

    var lines = ["# 會議翻譯記錄", "日期：\(displayDate)", "", "---", ""]
    for line in subtitleHistory {
        if !line.originalText.isEmpty {
            lines.append("> \(line.originalText)")
        }
        if !line.translatedText.isEmpty {
            lines.append(line.translatedText)
        }
        lines.append("")
    }

    let content = lines.joined(separator: "\n")

    do {
        try content.write(to: desktopURL, atomically: true, encoding: .utf8)
        self.status = "已儲存：~/Desktop/\(filename)"
    } catch {
        self.status = "匯出失敗：\(error.localizedDescription)"
    }
}
```

- [ ] **Step 3: Call `exportTranscript()` from `stop()`**

In `TranslatorViewModel.stop()`, add the export call at the end, before `status = "已停止"`:

```swift
func stop() {
    isRunning = false

    Task {
        await captureManager.stopCapture()
    }

    geminiConnection?.disconnect()
    geminiConnection = nil

    playbackManager.stop()
    exportTranscript()   // ← add this line
    status = "已停止"
}
```

- [ ] **Step 4: Build and verify**

```bash
bash build_app.sh
```

Expected: `✅ 打包完成！` with no new errors (existing warnings are fine).

- [ ] **Step 5: Manual test**

1. Open `MeetingTranslator.app`
2. Start a translation session with any audio source for ~30 seconds
3. Press "停止翻譯"
4. Check Desktop — a file named `meeting-YYYY-MM-DD-HH-mm.md` should exist
5. Open it — verify it contains original + translated lines in the correct format
6. Check status bar in app — should show `已儲存：~/Desktop/meeting-...md`

- [ ] **Step 6: Commit**

```bash
git add ContentView.swift
git commit -m "feat: auto-export bilingual transcript to Desktop on stop"
```

---

### Task 2: Floating Subtitle Window

**Files:**
- Create: `FloatingSubtitleWindow.swift`
- Modify: `TranslatorApp.swift`
- Modify: `build_app.sh` (add new file to compile list)

**Interfaces:**
- Consumes: `TranslatorViewModel.currentLine: SubtitleLine`, `TranslatorViewModel.isRunning: Bool`, `SubtitleLine.originalText: String`, `SubtitleLine.translatedText: String`
- Produces: `FloatingSubtitleWindow` class with `show()` and `hide()` methods; `FloatingSubtitleView` SwiftUI view

- [ ] **Step 1: Create `FloatingSubtitleWindow.swift`**

Create the file at the project root with this content:

```swift
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
```

- [ ] **Step 2: Update `TranslatorApp.swift` to manage the panel**

Replace the entire file content with:

```swift
import SwiftUI
import AppKit

@main
struct TranslatorApp: App {
    @StateObject private var viewModel = TranslatorViewModel()
    @State private var floatingWindow: FloatingSubtitleWindow?

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onAppear {
                    let panel = FloatingSubtitleWindow(viewModel: viewModel)
                    floatingWindow = panel
                }
                .onChange(of: viewModel.isRunning) { _ in
                    if viewModel.isRunning {
                        floatingWindow?.show()
                    } else {
                        floatingWindow?.hide()
                    }
                }
        }
        .windowStyle(HiddenTitleBarWindowStyle())
    }
}
```

- [ ] **Step 3: Update `ContentView` to accept a ViewModel parameter**

`TranslatorApp` now owns the ViewModel and passes it down. Update `ContentView.swift`:

Change the `ContentView` struct to accept an injected ViewModel instead of creating its own:

```swift
// CHANGE this line at the top of ContentView:
struct ContentView: View {
    @ObservedObject var viewModel: TranslatorViewModel  // was: @StateObject private var viewModel = TranslatorViewModel()
```

And remove the `@StateObject` init line. The rest of `ContentView` body stays identical.

- [ ] **Step 4: Add `FloatingSubtitleWindow.swift` to `build_app.sh`**

In `build_app.sh`, find the `swiftc` compile block and add the new file:

```bash
swiftc \
  -sdk "$SDK_PATH" \
  -O \
  -o "${MAC_OS_DIR}/${APP_NAME}" \
  TranslatorApp.swift \
  ContentView.swift \
  AudioCaptureManager.swift \
  AudioPlaybackManager.swift \
  GeminiLiveConnection.swift \
  FloatingSubtitleWindow.swift
```

- [ ] **Step 5: Build and verify**

```bash
bash build_app.sh
```

Expected: `✅ 打包完成！` with no new errors.

- [ ] **Step 6: Manual test**

1. Open `MeetingTranslator.app`
2. Press "開始即時翻譯" — floating panel should appear bottom-right
3. Verify panel is always on top of other windows (including Zoom/browser)
4. Verify original text appears small and gray, translation appears large and white
5. Drag the panel to a new position — relaunch the app and confirm it restores to that position
6. Press "停止翻譯" — panel should disappear

- [ ] **Step 7: Commit**

```bash
git add FloatingSubtitleWindow.swift TranslatorApp.swift ContentView.swift build_app.sh
git commit -m "feat: add always-on-top floating subtitle window with frosted glass"
```

---

### Task 3: Final Build + Push

- [ ] **Step 1: Full clean build**

```bash
bash build_app.sh
```

Expected: `✅ 打包完成！` with no new errors.

- [ ] **Step 2: End-to-end smoke test**

1. Start a session — floating panel appears
2. Let it run 30+ seconds to accumulate subtitle history
3. Stop — panel disappears, Desktop file created, status bar shows file path
4. Open the Desktop `.md` file — verify bilingual content is correct

- [ ] **Step 3: Push**

```bash
git push origin main
```
