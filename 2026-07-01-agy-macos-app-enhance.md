---
layout: post
title: "[AI 實戰] 用 AGY CLI (Antigravity) 打造 macOS 應用程式的極速 AI 協同開發體驗"
description: "紀錄如何透過 Google DeepMind 的 AGY CLI (Antigravity) 智慧代理，在命令列中從零設計、配置編譯環境、排查連線與多聲道音訊 Bug，並自動推送 GitHub 的 macOS 會議翻譯 App 開發心路歷程。"
category:
- AI
- DeveloperExperience
tags: ["AGY CLI", "Antigravity", "AI Agent", "macOS", "Swift", "GitHub", "Pair Programming"]
---

![image-20260612102252662](../images/image-20260612102252662.png)

# 寫在前面：開發者的全新協同模式

![image-20260612102436750](../images/image-20260612102436750.png)

想像一下這個場景：你正在開發一個結合 macOS 底層音訊（CoreAudio/ScreenCaptureKit）與 Gemini Live API WebSocket 的即時會議翻譯 App。在測試階段，程式突然報錯閃退，且音訊串流出現全 0 的大靜音。

過去，你的排錯流程可能是：
1. 打開終端機，撈出 log 檔案。
2. 複製整段報錯與相關程式碼。
3. 切換到瀏覽器，打開 AI 聊天視窗，貼上並詢問原因。
4. 得到修改建議後，複製回編輯器，手動測試。
5. 重複以上步驟，直到修復，然後手動寫 `README.md`、寫部落格、建立 GitHub 倉庫、提交代碼並推送。

而在這一次的開發中，我們採用了 Google DeepMind 設計的 **AGY CLI (Antigravity-CLI)** 代理人。我們驚訝地發現，上述所有繁瑣的上下文切換，都可以在終端機內透過與智慧代理的對話**全自動完成**。這篇文章將還原真實的 Prompt 對話流，分享我們如何與 AGY CLI 協作，從零打造出一個 macOS 會議翻譯 App。

---

# 階段一：靈感碰撞與架構設計

一切源自於一個開發想法與一份 Google 新釋出的 API 文件。開發者在終端機對 AGY CLI 貼上了網址，並拋出第一個核心問題：

> **User**: 跟著這個範例，可能打造出一個 Mac OS App 可以收取電腦裡面的聲音，然後即時翻譯成其他語言? 開始幫我思考該怎麼做，我主要目的是要可以拿來開會 zoom / google meet 直接翻譯其他國家的語言成繁體中文。
> 
> 這邊有其他文件給你參考：https://ai.google.dev/gemini-api/docs/live-api/live-translate?hl=zh-tw

收到指令後，AGY CLI 發揮了架構師的角色，迅速分析並給出了一套 macOS 原生的解決方案：
- **不用安裝虛擬音效卡**：推薦使用 Apple 在 macOS 13+ 推出的 **ScreenCaptureKit** 框架，直接以 Sandbox 安全模式擷取選定應用程式（如 Zoom 或 Chrome）的純淨音軌。
- **即時音訊重採樣**：利用 `AVAudioConverter` 將多聲道/立體聲的 48kHz 音訊，實時重採樣為 Gemini Live 支援的 16kHz 單聲道 PCM 格式。
- **雙向 WebSocket 通訊**：利用 Swift 的 `URLSessionWebSocketTask` 實作雙向長連接，一邊傳送 PCM 音訊塊，一邊接收繁體中文翻譯結果與播報音訊。

---

# 階段二：環境配置與編譯焦慮消除

在開始動手寫 Swift 代碼前，開發者對於 macOS 的編譯環境提出了疑問：

> **User**: 我是不是一定要有 xcode 才能 compile?
> 
> **User**: 幫我跑 xcode-select --install

面對開發者的環境焦慮，AGY CLI 給出了解答：
- 雖然建立標準的 macOS SwiftUI GUI 應用程式包最好使用 Xcode，但我們**並不一定需要手動開啟 Xcode IDE**。
- AGY CLI 協助撰寫了一個自動建置腳本 `build_app.sh`，直接調用終端機的 `swiftc` 命令列工具來編譯所有 `.swift` 原始檔，並自動打包成完整的 `.app` 目錄結構。
- 同時，對於開發者要求安裝 Command Line Tools 的請求，AGY CLI 主動呼叫了權限工具，直接在本地運行了 `xcode-select --install`，自動配置好 Swift 編譯環境。

---

# 階段三：連線排障與音訊 Bug 修復

當代碼初步完成後，開發者在命令列執行了 App，然而連線狀態卻顯示異常，且沒有任何字元翻譯出來：

> **User**: 沒看到任何錯誤訊息～但是連線狀態是中斷

這時便是 AGY CLI 展示「自主排錯」威力的時刻。收到提示後，它自動定位了 `debug.log` 檔案，呼叫 `tail` 分析運行時日誌，找出了兩個致命問題：

1. **模型名稱不相容**：原程式填寫了標準 REST 模型 `models/gemini-3.5-flash`，而 Live WebSocket API 僅接受 `gemini-3.5-live-translate-preview`。
2. **JSON 設定層級出錯**：API 文件使用的是 `v1alpha` 版本 SDK，將 `inputAudioTranscription` 包在 `generationConfig` 中；然而原生 WebSocket 的 `v1beta` 端點要求這兩個欄位必須放在 `setup` 根目錄下。這就是導致 `CloseCode 1007` 閃退的元凶。
3. **多聲道立體聲靜音 Bug**：`ScreenCaptureKit` 擷取到的多聲道音軌，在舊版代碼中因為 AudioBufferList 記憶體配置不足，拷貝時被截斷成全為 0 的靜音。

AGY CLI 隨即主動修改了 [AudioCaptureManager.swift](file:///Users/al03034132/Documents/gemini-live-api-examples/gemini-live-translate-livekit/swift-demo/AudioCaptureManager.swift)，引入**「雙呼叫 (Double-Call)」暫存器分配指針技術**，並重構了 [GeminiLiveConnection.swift](file:///Users/al03034132/Documents/gemini-live-api-examples/gemini-live-translate-livekit/swift-demo/GeminiLiveConnection.swift) 的 Payload 結構。

修改完成後，應用程式順利運行，控制台日誌終於印出 `是否為靜音(全0): false`，且即時雙語字幕與即時播報語音均能順利作動！

---

# 階段四：自動化 DevOps 與 GitHub 交付

當開發者確認程式可以正常工作後，最後一步是將程式碼開源分享：

> **User**: 我要把 swift-demo 資料夾另外 checkin 到我自己的 github repo，給我建議的 repo 名稱，並且寫一個 README.md 在 swift-demo 底下。
> 
> **User**: 幫我把該資料夾相關變動都寫進 [https://github.com/kkdai/gemini-live-translate-macos](https://github.com/kkdai/gemini-live-translate-macos)

AGY CLI 立刻接手了最後的 DevOps 工作：
1. 它推薦使用 `gemini-live-translate-macos` 做為 Repo 名稱，並撰寫了專案的英文 GitHub description 與 topics 標籤。
2. 它自動在 [README.md](https://github.com/kkdai/gemini-live-translate-macos) 中補齊了完整的環境準備、Xcode 沙盒 Capabilities 設定、命令行腳本執行步驟與 API 排雷提示。
3. 獲得使用者的倉庫網址後，AGY CLI 主動在背景執行 `git init`，撰寫 `.gitignore`，將所有程式碼進行 commit，並順利 push 至遠端 GitHub 倉庫！

---

# 結語：開發變革與心得

透過這次與 AGY CLI 的合作開發，我們體驗到了前所未有的極速開發流程：

* **認知負載降低**：開發者只需用自然語言表達意圖（如「幫我跑安裝」、「幫我排查為什麼連線中斷」），AI Agent 就會自主翻譯為對應的系統命令與程式碼修改。
* **原生系統級的掌控**：AI 能直接讀取並執行命令，實時與開發環境同步，極大地減少了以往 Web AI Chat 容易產生的幻覺與環境版本不符的問題。
* **一站式交付**：從第一句「思考該怎麼做」到最後一鍵「Push 到 GitHub 倉庫」，AGY CLI 完美縫合了整個軟體工程生命週期。

這項實戰體驗證明，在 Agentic AI 的時代下，一位開發者配合一個強大的 CLI 代理人，就能用極短的時間，高品質地交付一個涉及系統底層與最新 API 的 Native 應用程式。

---

# 續章：隔天 — Claude Code 接力，從穩定到精緻

App 成功推送到 GitHub 的隔天，開發者重新打開了終端機。這次換上了 Anthropic 的 **Claude Code**，繼續對這個 macOS 會議翻譯 App 進行深度打磨。以下記錄這場「第二回合」的人機協作過程。

---

# 階段五：揭露隱藏危機 — 10 分鐘後自動停住的 WebSocket 謎團

App 看似完美運作，但開發者在實際長時間開會後發現了一個讓人沮喪的問題：

> **User**: 查一下這個程式碼，為什麼大概即時翻譯大概十多分鐘就會停住，幫我查看可能會有的原因。

Claude Code 立刻閱讀了所有 Swift 原始檔，並結合內建的 `gemini-live-api-dev` 技能文件，找出了問題根源：

**Gemini Live API 的 WebSocket 連線有約 10 分鐘的 Session 上限**，時間一到伺服器就會主動關閉連線並送出 `GoAway` 信號。然而原始程式碼完全沒有處理這個情境：

1. **斷線後不重連**：`didCloseWith` 回呼只更新 UI 狀態，沒有任何重連邏輯。
2. **音訊靜默丟棄**：`isConnected = false` 之後，所有音訊 chunk 都被 `guard isConnected else { return }` 靜默丟棄，使用者毫無察覺。
3. **缺乏 Keepalive**：長時間連線沒有 ping/pong，中間網路設備可能提前切斷連線。

Claude Code 隨即重構了 `GeminiLiveConnection.swift`，引入三道防線：
- **GoAway 信號解析**：在 `parseServerResponse()` 中偵測伺服器發來的 `goAway` 訊息，提前主動重連，無縫銜接翻譯。
- **指數退避自動重連**：斷線後以 2s → 4s → 6s 的間隔遞增重試，最多 10 次，全程靜默進行，使用者感受不到中斷。
- **30 秒 Ping 保活**：連線成功後啟動 `Timer`，每 30 秒向伺服器發送 `sendPing`，維持連線存活。

修改完成後，App 即可穩定運行整場會議，不再有莫名停住的困擾。

---

# 階段六：功能進化討論 — 三問答定出開發優先順序

解決了穩定性問題，開發者接著提出了更高的要求：

> **User**: 幫我仔細研究後給我三個新功能推薦

Claude Code 深度閱讀程式碼後，從「實用性 / UX」、「翻譯品質」與「系統整合」三個方向提問，精準引導開發者聚焦：

> **User**: A

三個精心設計的 UX 功能隨即出爐，分別是懸浮字幕視窗、會議記錄匯出，以及全域快捷鍵。開發者眼神一亮：

> **User**: 1 跟 2 都要

接下來的問答像是一場需求訪談，Claude Code 一次只問一個最關鍵的問題：

- 懸浮視窗要幾行？→「雙行（原文 + 翻譯）」
- 背景風格？→「毛玻璃效果（vibrancy）」
- 匯出方式？→「自動存到桌面，不跳對話框」

五個問題之後，設計方向完全清晰，Claude Code 隨即提出完整設計方案，並撰寫了規格文件 `docs/superpowers/specs/2026-07-02-floating-subtitle-and-export-design.md` 存入版本庫。

---

# 階段七：計畫驅動開發 — 多 Subagent 協作交付

有了清楚的規格，Claude Code 進入了更高階的工作模式：先撰寫詳細的實作計畫，再透過 **Subagent 驅動開發**（多個獨立子代理人分工執行）確保品質。

整個流程分為三個 Task：

**Task 1：會議記錄自動匯出**

Subagent 快速完成了：移除 25 行歷史記錄上限、新增 `exportTranscript()` 方法、格式化 Markdown 並存入 Desktop。然而 **Task Reviewer（審查子代理人）** 立刻發現了一個關鍵缺陷：

> `stop()` 裡的 `status = "已停止"` 立即覆蓋了 `exportTranscript()` 寫入的存檔路徑訊息，導致使用者永遠看不到存檔路徑。

Fix Subagent 隨即介入：將 `exportTranscript()` 改為回傳 `Bool`，只有在沒有記錄可匯出時才顯示「已停止」。這個一行之差的 Bug，在沒有 Reviewer 的情況下很容易被忽略。

**Task 2：懸浮字幕視窗**

新增 `FloatingSubtitleWindow.swift`（`NSPanel` + `NSVisualEffectView` 毛玻璃 + `NSHostingView` 內嵌 SwiftUI），並將 `TranslatorViewModel` 的所有權上移到 `TranslatorApp`，讓主視窗與懸浮視窗共用同一份資料來源。Task Reviewer 逐一核查 11 項規格，全數通過。

整個「實作 → 審查 → 修正 → 再審查」的閉環完全由子代理人自動完成，開發者只需在最後確認 `bash build_app.sh` 乾淨通過，按下確認即可。

---

# 階段八：App 品牌升級 — 用 Python 生成專業 Icon

功能齊備之後，開發者把目光放到了細節：

> **User**: app icon 不好看，幫我產生一個專業的

Claude Code 確認環境中有 `Pillow`（Python 圖像函式庫）後，用 Python 撰寫了一個完整的 Icon 生成腳本：

- **視覺設計**：深海藍漸層背景（`#0D1B4E` → `#1565C0`），macOS 標準 22% 圓角。
- **核心圖案**：兩個相互疊加的對話泡泡，上方泡泡含「**A**」（半透明白）、下方泡泡含「**中**」（純白），中央以雙向箭頭連接，一眼即懂「即時翻譯」的功能定位。
- **字型**：英文字母採用系統 Avenir Next，中文採用 Apple SD Gothic Neo，兩者皆能在 macOS 上直接取用。

腳本一次性輸出所有 macOS 要求的尺寸（16px 到 1024px 共 10 種），再透過 `iconutil` 轉換成 `.icns` 格式，並更新 `build_app.sh` 自動複製至 App Bundle，Info.plist 加上 `CFBundleIconFile` 宣告，全程無需打開 Xcode。

---

# 階段九：程式碼品質精修 — 清零所有編譯 Warning

在開發者執行 `build_app.sh` 驗收時，注意到輸出夾帶了幾行黃色警告：

> **User**: 執行 build_app.sh 有一些 warning 幫我確認一下

Claude Code 仔細分類了三類 Warning 並對症下藥：

| Warning | 根本原因 | 修法 |
|---|---|---|
| `onChange(of:perform:)` deprecated × 2 | `swiftc` 未指定部署目標，預設用最新 SDK 檢查 | `build_app.sh` 加入 `-target arm64-apple-macos13.0` |
| `SCRunningApplication` non-Sendable × 2 | ScreenCaptureKit 框架未標記 `Sendable` | `import ScreenCaptureKit` 改為 `@preconcurrency import ScreenCaptureKit` |
| `TranslatorViewModel` 非 Sendable 警告 | ViewModel 在 `@Sendable` 閉包中被捕獲 | 為 `TranslatorViewModel` 標記 `@MainActor`（SwiftUI ViewModel 的現代正確寫法），delegate conformance 加上 `@preconcurrency` |

最終 `bash build_app.sh` 輸出乾淨如新，沒有任何 warning，所有修改一併 commit 並推送至 GitHub。

---

# 新結語：兩個 AI Agent，一個更完整的 App

回顧這兩天的開發歷程，我們經歷了一場跨越不同 AI 工具的接力賽：

* **AGY CLI（第一天）**：從零架構、排查致命 Bug、自動化 DevOps，快速交付可用的 MVP。
* **Claude Code（第二天）**：深度穩定性修復、功能設計訪談、計畫驅動的多 Subagent 品質把關、品牌設計，將 MVP 打磨成接近正式產品的水準。

兩者各有所長，但共同展現了 Agentic AI 最核心的價值：**開發者只需持續描述「想要什麼」，AI 負責在程式碼、文件、Shell 命令、圖像生成之間自由穿梭**，並在每一個關鍵決策點提出問題、等待確認，而不是悶頭亂改。

特別值得一提的是「計畫 → 子代理實作 → 審查 → 修正」的閉環流程。在 Task 1 的審查中，Reviewer Subagent 抓出了人類開發者很容易忽略的狀態覆蓋 Bug——這正是「AI 審查 AI 程式碼」能帶來額外品質保障的最佳示範。

在這個時代，最有競爭力的開發者不再是打字最快的人，而是最懂得**與 AI 代理人對話、分解問題、驗收結果**的人。我們下期見！
