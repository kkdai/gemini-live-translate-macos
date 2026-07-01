# Design: Floating Subtitle Window + Meeting Transcript Export

Date: 2026-07-02  
Status: Approved

---

## Overview

Two UX features that address the core pain points of daily meeting use:

1. **Floating Subtitle Window** — always-on-top overlay so users never need to switch windows during a meeting
2. **Meeting Transcript Auto-Export** — saves the full bilingual transcript to Desktop when translation stops

---

## Feature 1: Floating Subtitle Window

### Goal

Allow users to see the live translation overlaid on top of their meeting app (Zoom, Meet, Teams) without switching windows.

### Architecture

**New file: `FloatingSubtitleWindow.swift`**

- Subclass of `NSPanel` with `level = .floating` and `styleMask` including `.nonactivatingPanel` so it doesn't steal focus from the meeting app
- Background: `NSVisualEffectView` with `material = .hudWindow` for macOS frosted glass effect
- Content: `NSHostingView` wrapping a SwiftUI `FloatingSubtitleView` that binds to `TranslatorViewModel.currentLine`
- Draggable by the user; position persisted to `UserDefaults` key `floatingWindowFrame`
- Default position: bottom-right corner of the main screen

**Changes to `TranslatorApp.swift`**

- Create and hold a `FloatingSubtitleWindow` instance at app launch
- Show the panel when `viewModel.isRunning` becomes `true`
- Hide the panel when `viewModel.isRunning` becomes `false`

### Visual Layout

```
┌─────────────────────────────────────┐  ← frosted glass (NSVisualEffectView)
│  This feature is really important   │  ← original text, 12pt, gray, italic
│  這個功能非常重要                     │  ← translation, 16pt, white, bold
└─────────────────────────────────────┘
  min-width: 300pt, max-width: 600pt, auto-height
```

### Behaviour

| State | Panel |
|---|---|
| App opens | Panel hidden |
| Translation starts | Panel appears at last saved position |
| `currentLine` updates | Text updates live |
| Sentence rotates | Panel shows new `currentLine` |
| Translation stops | Panel hides |
| User drags panel | New frame saved to UserDefaults |

---

## Feature 2: Meeting Transcript Auto-Export

### Goal

Preserve the complete bilingual meeting record after each session. Currently the history is capped at 25 lines and lost on stop.

### Architecture

**Changes to `TranslatorViewModel`**

- Remove the 25-line cap on `subtitleHistory` — accumulate the full session
- Add `exportTranscript()` private method
- Call `exportTranscript()` from `stop()` only when `subtitleHistory` is non-empty
- After export, update `status` to show the saved file path

**Export logic**

- Output directory: `~/Desktop/`
- Filename: `meeting-YYYY-MM-DD-HH-mm.md`
- Write using `FileManager` + `String.write(toFile:atomically:encoding:)`

### Output Format

```markdown
# 會議翻譯記錄
日期：2026-07-02 14:30

---

> This feature is really important
這個功能非常重要

> Let me show you the demo
讓我展示一下 Demo
```

### Behaviour

| Condition | Result |
|---|---|
| Stop pressed, history non-empty | Auto-save to Desktop, show path in status bar |
| Stop pressed, history empty | Skip export silently |
| File write fails | Show error in status bar, do not crash |

---

## Files Changed

| File | Change |
|---|---|
| `FloatingSubtitleWindow.swift` | New — NSPanel + NSVisualEffectView + FloatingSubtitleView |
| `TranslatorApp.swift` | Hold panel reference, show/hide on isRunning changes |
| `ContentView.swift` | Remove 25-line cap; add exportTranscript() + stop() call |

---

## Out of Scope

- Manual "Save As" dialog (decided: auto-save only)
- Export to formats other than Markdown
- Global hotkey (separate feature, not in this spec)
