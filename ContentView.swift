import SwiftUI
import ScreenCaptureKit

struct SubtitleLine: Identifiable, Equatable {
    let id = UUID()
    var originalText: String = ""
    var translatedText: String = ""
}

class TranslatorViewModel: ObservableObject, AudioCaptureDelegate, GeminiLiveConnectionDelegate {
    @Published var apiKey: String = ""
    @Published var status: String = "未連線"
    
    // 當前正在接收並翻譯的句子
    @Published var currentLine = SubtitleLine()
    // 歷史翻譯字幕列表
    @Published var subtitleHistory: [SubtitleLine] = []
    
    @Published var shareableApps: [SCRunningApplication] = []
    @Published var selectedApp: SCRunningApplication?
    
    // 允許用戶自由輸入任何模型名稱
    @Published var selectedModel = "gemini-3.5-live-translate-preview"
    
    @Published var isRunning = false
    @Published var showBilingual = true         // 是否顯示中英雙語對照字幕
    @Published var enableVoiceTranslation = true // 是否播放即時中文語音同聲傳譯
    
    private let captureManager = AudioCaptureManager()
    private let playbackManager = AudioPlaybackManager()
    private var geminiConnection: GeminiLiveConnection?
    
    init() {
        captureManager.delegate = self
        if let savedKey = UserDefaults.standard.string(forKey: "GeminiAPIKey") {
            self.apiKey = savedKey
        }
        if let savedModel = UserDefaults.standard.string(forKey: "GeminiModel") {
            self.selectedModel = savedModel
        }
    }
    
    func refreshApps() {
        Task {
            let apps = await captureManager.fetchShareableApps()
            DispatchQueue.main.async {
                self.shareableApps = apps
                if self.selectedApp == nil, let firstApp = apps.first(where: { 
                    let name = $0.applicationName
                    return name.contains("Zoom") || name.contains("Chrome") || name.contains("Safari") || name.contains("Meet") || name.contains("Teams")
                }) {
                    self.selectedApp = firstApp
                } else if self.selectedApp == nil {
                    self.selectedApp = apps.first
                }
            }
        }
    }
    
    func start() {
        guard !apiKey.isEmpty else {
            status = "錯誤: 請輸入 Gemini API Key"
            return
        }
        guard let app = selectedApp else {
            status = "錯誤: 請選擇要擷取音訊的應用程式"
            return
        }
        
        UserDefaults.standard.set(apiKey, forKey: "GeminiAPIKey")
        UserDefaults.standard.set(selectedModel, forKey: "GeminiModel")
        
        status = "連線中..."
        isRunning = true
        currentLine = SubtitleLine()
        subtitleHistory = []
        
        // 1. 初始化連線 (使用用戶輸入的模型)
        geminiConnection = GeminiLiveConnection(apiKey: apiKey, modelName: selectedModel)
        geminiConnection?.delegate = self
        geminiConnection?.connect()
        
        // 2. 開始音訊擷取
        Task {
            await captureManager.startCapture(for: app)
        }
    }
    
    func stop() {
        isRunning = false
        
        Task {
            await captureManager.stopCapture()
        }
        
        geminiConnection?.disconnect()
        geminiConnection = nil
        
        playbackManager.stop()
        exportTranscript()
        status = "已停止"
    }

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
    
    // MARK: - AudioCaptureDelegate
    func didCaptureAudioData(_ data: Data) {
        geminiConnection?.sendAudioChunk(data)
    }
    
    func didUpdateApplications(_ apps: [SCRunningApplication]) {
        DispatchQueue.main.async {
            self.shareableApps = apps
        }
    }
    
    // MARK: - GeminiLiveConnectionDelegate
    
    // 收到原始會議發言字句 (例如英文)
    func didReceiveInputTranscription(_ text: String) {
        currentLine.originalText += text
        checkAndRotateSubtitle(text: text)
    }
    
    // 收到翻譯後的繁中字句
    func didReceiveOutputTranscription(_ text: String) {
        currentLine.translatedText += text
        checkAndRotateSubtitle(text: text)
    }
    
    // 收到翻譯後的中文語音 PCM 資料，即時播音
    func didReceiveAudioData(_ data: Data) {
        if enableVoiceTranslation {
            playbackManager.playAudioData(data)
        }
    }
    
    func didUpdateConnectionStatus(_ status: String) {
        self.status = status
    }

    func didPermanentlyDisconnect() {
        isRunning = false
    }
    
    private func checkAndRotateSubtitle(text: String) {
        let sentenceEndings = ["。", "？", "！", ".", "?", "!", "\n"]
        if sentenceEndings.contains(where: { text.contains($0) }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self = self else { return }
                
                if !self.currentLine.originalText.isEmpty || !self.currentLine.translatedText.isEmpty {
                    self.subtitleHistory.append(self.currentLine)
                    self.currentLine = SubtitleLine()
                }
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = TranslatorViewModel()
    
    var body: some View {
        VStack(spacing: 14) {
            Text("會議即時雙語翻譯工具")
                .font(.title)
                .bold()
                .padding(.top)
            
            // API Key 設定
            VStack(alignment: .leading, spacing: 4) {
                Text("1. 設定 Gemini API Key")
                    .font(.headline)
                SecureField("請輸入 Gemini API Key", text: $viewModel.apiKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            .padding(.horizontal)
            
            // 模型與來源 App 設定
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("2. 輸入或快速選擇 Gemini 模型")
                        .font(.headline)
                    TextField("請輸入模型名稱", text: $viewModel.selectedModel)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .disabled(viewModel.isRunning)
                    
                    HStack(spacing: 8) {
                        Button("3.5-Translate-Preview") { viewModel.selectedModel = "gemini-3.5-live-translate-preview" }
                            .buttonStyle(BorderlessButtonStyle())
                            .font(.caption)
                            .foregroundColor(.blue)
                        
                        Button("2.0-Flash-Exp") { viewModel.selectedModel = "gemini-2.0-flash-exp" }
                            .buttonStyle(BorderlessButtonStyle())
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("3. 選擇會議來源 App")
                            .font(.headline)
                        Spacer()
                        Button(action: { viewModel.refreshApps() }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .disabled(viewModel.isRunning)
                    }
                    Picker("目標 App", selection: $viewModel.selectedApp) {
                        if viewModel.shareableApps.isEmpty {
                            Text("點擊重新整理").tag(nil as SCRunningApplication?)
                        } else {
                            ForEach(viewModel.shareableApps, id: \.processID) { app in
                                Text(app.applicationName).tag(app as SCRunningApplication?)
                            }
                        }
                    }
                    .pickerStyle(DefaultPickerStyle())
                    .disabled(viewModel.isRunning)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)
            
            // 開關設定與控制按鈕
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("顯示雙語對照 (原文/中文)", isOn: $viewModel.showBilingual)
                        .toggleStyle(CheckboxToggleStyle())
                    
                    Toggle("啟用中文語音播放 (即時同傳) 🔊", isOn: $viewModel.enableVoiceTranslation)
                        .toggleStyle(CheckboxToggleStyle())
                }
                
                Spacer()
                
                if !viewModel.isRunning {
                    Button(action: { viewModel.start() }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("開始即時翻譯")
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                } else {
                    Button(action: { viewModel.stop() }) {
                        HStack {
                            Image(systemName: "stop.fill")
                            Text("停止翻譯")
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal)
            
            Divider()
            
            // 字幕顯示區
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("連線狀態:")
                        .font(.subheadline)
                        .bold()
                    Text(viewModel.status)
                        .font(.subheadline)
                        .foregroundColor(viewModel.isRunning ? .green : .gray)
                    Spacer()
                }
                
                Text("即時翻譯字幕:")
                    .font(.headline)
                
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(viewModel.subtitleHistory) { line in
                                VStack(alignment: .leading, spacing: 4) {
                                    if viewModel.showBilingual && !line.originalText.isEmpty {
                                        Text(line.originalText)
                                            .foregroundColor(.gray)
                                            .font(.system(size: 14, design: .monospaced))
                                    }
                                    Text(line.translatedText)
                                        .foregroundColor(.primary)
                                        .font(.system(size: 16, weight: .medium))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            
                            if !viewModel.currentLine.originalText.isEmpty || !viewModel.currentLine.translatedText.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    if viewModel.showBilingual && !viewModel.currentLine.originalText.isEmpty {
                                        Text(viewModel.currentLine.originalText)
                                            .foregroundColor(.blue.opacity(0.8))
                                            .font(.system(size: 15, design: .monospaced))
                                    }
                                    if !viewModel.currentLine.translatedText.isEmpty {
                                        Text(viewModel.currentLine.translatedText)
                                            .foregroundColor(.primary)
                                            .font(.system(size: 18, weight: .bold))
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("currentLine")
                            } else if viewModel.subtitleHistory.isEmpty {
                                Text("等待音訊輸入... (請確保選擇正確的會議 App 並在該 App 中有聲音播放)")
                                    .foregroundColor(.gray)
                                    .font(.italic(.system(size: 14))())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding()
                    }
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(8)
                    .border(Color.gray.opacity(0.2), width: 1)
                    .onChange(of: viewModel.subtitleHistory) { _ in
                        withAnimation {
                            proxy.scrollTo("currentLine", anchor: .bottom)
                        }
                    }
                }
            }
            .padding([.horizontal, .bottom])
        }
        .frame(minWidth: 550, minHeight: 670)
        .onAppear {
            viewModel.refreshApps()
        }
    }
}
