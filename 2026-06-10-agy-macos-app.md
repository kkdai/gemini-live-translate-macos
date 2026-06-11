---
layout: post
title: "[AI 實戰] 用 AGY CLI (Antigravity) 打造 macOS 應用程式的極速 AI 協同開發體驗"
description: "紀錄如何透過 Google DeepMind 的 AGY CLI (Antigravity) 智慧代理，在命令列中進行 macOS 音訊擷取與 Gemini Live API 翻譯 App 的開發、Log 排查、問題修正與自動 Git 推送的全自動化開發體驗。"
category:
- AI
- DeveloperExperience
tags: ["AGY CLI", "Antigravity", "AI Agent", "macOS", "Swift", "GitHub", "Pair Programming"]
---

![AGY CLI Developer Experience](../images/agy_cli_dx.png)

# 寫在前面：開發者的全新協同模式

想像一下這個場景：你正在開發一個結合 macOS 底層音訊（CoreAudio/ScreenCaptureKit）與 Gemini Live API WebSocket 的即時會議翻譯 App。在測試階段，程式突然報錯閃退，且音訊串流出現全 0 的大靜音。

過去，你的排錯流程可能是：
1. 打開終端機，撈出 log 檔案。
2. 複製整段報錯與相關程式碼。
3. 切換到瀏覽器，打開 AI 聊天視窗，貼上並詢問原因。
4. 得到修改建議後，複製回編輯器，手動測試。
5. 重複以上步驟，直到修復，然後手動寫 `README.md`、寫部落格、建立 GitHub 倉庫、提交代碼並推送。

而在這一次的開發中，我們採用了 Google DeepMind 設計的 **AGY CLI (Antigravity-CLI)** 代理人。我們驚訝地發現，上述所有繁瑣的上下文切換，都可以在終端機內透過與智慧代理的對話**全自動完成**。這篇文章將分享我們如何利用 AGY CLI 協同開發一個 macOS App 的真實體驗。

---

# 什麼是 AGY CLI (Antigravity)？

**AGY CLI** 是一個具備自主代理能力（Agentic AI）的命令列編程助手。與一般的 Chatbot 不同，它擁有以下幾項核心的「手腳」（Tools）：
- **程式碼閱讀與搜尋能力**：能自主檢視整個專案目錄的架構，並精確讀取特定程式檔案。
- **檔案編輯與寫入能力**：支援單區塊與多區塊的精確程式碼替換，無須手動複製貼上。
- **終端機指令執行權**：經由使用者確認後，能直接在本地運行編譯、打包、查看 log、執行 Git 操作等命令。
- **高自主排錯思維**：能自行分析日誌，推導問題根源，並提出完整的修復方案。

---

# 實戰情境：MeetingTranslator 的排錯與建置

在我們的 macOS 會議翻譯 App 測試中，我們在終端機執行了編譯好的二進位檔，但 WebSocket 連線隨即被伺服器切斷（CloseCode 1007 與 1008），且音訊發送全為靜音。

此時，我們對 AGY CLI 下達了簡單的指令：
> **User**: check log (幫我看 log)

### 1. 自主定位與 Log 分析
收到指令後，AGY CLI 自主搜尋了目錄，找到了生成的 `debug.log` 檔案，並在終端機背景呼叫 `tail -n 150 debug.log` 進行檢索。

它迅速抓出了兩個關鍵報錯：
1. `Unknown name "inputAudioTranscription" at 'setup.generation_config'`：這是一個 JSON Payload 結構配置錯誤。
2. `models/gemini-3.5-flash is not found for API version v1beta`：這是一個模型選用錯誤。

### 2. 直擊痛點：解決 macOS 多聲道音訊記憶體拷貝 Bug
除了連線問題，AGY CLI 還注意到日誌中音訊區塊的發送狀態：`是否為靜音(全0): true`。它隨即自主開啟了 [AudioCaptureManager.swift](file:///Users/al03034132/Documents/gemini-live-api-examples/gemini-live-translate-livekit/swift-demo/AudioCaptureManager.swift) 來查看音訊緩衝區的處理 logic。

它發現程式在處理 `ScreenCaptureKit` 傳回的立體聲/多聲道音訊時，因為使用了靜態大小分配的 `AudioBufferList`，導致複製多聲道資料時記憶體溢位而截斷成全空值（靜音）。

AGY CLI 隨即提出了**「雙呼叫 (Double-Call)」暫存器分配方案**，並直接對 [AudioCaptureManager.swift](file:///Users/al03034132/Documents/gemini-live-api-examples/gemini-live-translate-livekit/swift-demo/AudioCaptureManager.swift) 與 [GeminiLiveConnection.swift](file:///Users/al03034132/Documents/gemini-live-api-examples/gemini-live-translate-livekit/swift-demo/GeminiLiveConnection.swift) 進行了精確的程式碼重寫。

這項修改涉及到了 Swift 的 `UnsafeMutablePointer` 指針操作以及 macOS 的 Core Audio 框架，若是人類開發者手動查閱文檔並撰寫，通常需要耗費數小時；而 AGY CLI 在不到一分鐘內即完成重構並成功修復！

---

# 自動化 DevOps：從撰寫文檔到 GitHub 推送

程式碼修改完畢且測試成功後，我們向 AGY CLI 提出了進一步的發布需求：
> **User**: 我要把 swift-demo 資料夾另外 checkin 到我自己的 GitHub repo。給我建議的 repo 名稱，並且寫一個 README.md 在 swift-demo 底下。

此時，AGY CLI 的自主代理能力得到了最完美的展現：

1. **命名與描述建議**：它提出了 `gemini-live-translate-macos` 這個貼切的 Repository 名稱，並主動提供了 GitHub 專案的英文 description 與分類 topics。
2. **自動撰寫技術文檔**：它自動撰寫了排版精美的 [README.md](file:///Users/al03034132/Documents/gemini-live-api-examples/gemini-live-translate-livekit/swift-demo/README.md)（涵蓋詳細的 Xcode Sandbox 權限設定與 `build_app.sh` 命令行編譯說明）以及技術部落格。
3. **一鍵完成 Git 初始化與遠端推送**：
   在得到遠端 Git 地址（`git@github.com:kkdai/gemini-live-translate-macos.git`）後，AGY CLI 主動在終端機內串接並執行了以下複合指令：
   ```bash
   git init && \
   echo "MeetingTranslator.app/" >> .gitignore && \
   echo "debug.log" >> .gitignore && \
   git add .gitignore *.swift build_app.sh README.md ... && \
   git commit -m "Initial commit..." && \
   git branch -M main && \
   git remote add origin git@github.com:kkdai/... && \
   git push -u origin main
   ```
   使用者只需要在 CLI 中點擊 **Approve**，AGY CLI 就在幾秒鐘內幫我們建置好了一個完整的 GitHub 開源專案！

---

# 開發變革與心得

透過這一次與 AGY CLI 的合作開發，我們總結出以下幾點極致的開發體驗變革：

### 1. 認知負載 (Cognitive Load) 歸零
開發者不需要再分神去處理「如何複製程式碼給 AI」、「如何把 AI 給的程式碼剪貼回專案」等重複性動作。AGY CLI 直接作為你的 terminal shell 與 editor 的延伸，你只需專注於**「下達高層級的設計與排錯指令」**。

### 2. 原生系統級的掌控
由於代理人能夠直接讀取並執行命令行，它能實時與你的開發環境同步（例如讀取編譯失敗日誌、確認 git 狀態、直接編譯代碼）。這讓 AI 的修復建議是「絕對與你當前系統狀態相符的」，極大地減少了以往 Web AI Chat 容易產生的幻覺與環境版本不符的問題。

### 3. 一站式交付體驗
從排錯、代碼優化、撰寫文檔到自動推送 GitHub 倉庫，AGY CLI 將整個軟體工程的生命週期緊密地縫合在一個工作流中。這種「對話即交付」的體驗，正是未來軟體開發的新常態。

---

# 結論

AI 程式助理已經從簡單的「程式碼自動補全（Auto-complete）」演進到如今「自動化代理人（Autonomous Agent）」的時代。藉由像 AGY CLI (Antigravity) 這樣的工具，一個人在一下午內打造、測試並發布一個 Native macOS App 不再是難事。

如果您也想體驗極速的命令行開發，不妨也給自己配置一個 AGY CLI 助手，我們下期見！
