import Foundation

protocol GeminiLiveConnectionDelegate: AnyObject {
    func didReceiveInputTranscription(_ text: String)
    func didReceiveOutputTranscription(_ text: String)
    func didReceiveAudioData(_ data: Data)
    func didUpdateConnectionStatus(_ status: String)
    func didPermanentlyDisconnect()
}

class GeminiLiveConnection: NSObject, URLSessionWebSocketDelegate {
    weak var delegate: GeminiLiveConnectionDelegate?

    private var webSocketTask: URLSessionWebSocketTask?
    private var isConnected = false
    private var chunkCount = 0

    private let apiKey: String
    private let modelName: String

    private let host = "generativelanguage.googleapis.com"
    private let path = "/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"

    private var isIntentionalDisconnect = false
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10
    private var pingTimer: Timer?

    private lazy var session: URLSession = {
        return URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }()

    init(apiKey: String, modelName: String) {
        self.apiKey = apiKey
        self.modelName = modelName
        super.init()
    }

    func connect() {
        isIntentionalDisconnect = false
        reconnectAttempts = 0
        performConnect()
    }

    private func performConnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false

        var urlComponents = URLComponents()
        urlComponents.scheme = "https"
        urlComponents.host = host
        urlComponents.path = path
        urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        guard let url = urlComponents.url else {
            print("無效的 API URL")
            return
        }

        let wsUrlString = url.absoluteString.replacingOccurrences(of: "https://", with: "wss://")
        guard let wsUrl = URL(string: wsUrlString) else { return }

        let statusMsg = reconnectAttempts == 0 ? "連線中..." : "重新連線中... (第 \(reconnectAttempts) 次)"
        DispatchQueue.main.async { self.delegate?.didUpdateConnectionStatus(statusMsg) }

        webSocketTask = session.webSocketTask(with: wsUrl)
        webSocketTask?.resume()

        receiveMessage()
        sendSetupConfig()
    }

    func disconnect() {
        isIntentionalDisconnect = true
        stopPingTimer()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        delegate?.didUpdateConnectionStatus("已斷線")
    }

    func sendAudioChunk(_ data: Data) {
        guard isConnected else { return }

        chunkCount += 1
        if chunkCount % 100 == 0 {
            let isSilent = data.allSatisfy { $0 == 0 }
            print("📊 [WebSocket] 已發送 \(chunkCount) 個音訊區塊 | 大小: \(data.count) bytes | 是否為靜音(全0): \(isSilent)")
        }

        let base64Audio = data.base64EncodedString()

        let message: [String: Any] = [
            "realtimeInput": [
                "audio": [
                    "data": base64Audio,
                    "mimeType": "audio/pcm;rate=16000"
                ]
            ]
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: message, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                let wsMessage = URLSessionWebSocketTask.Message.string(jsonString)
                webSocketTask?.send(wsMessage) { error in
                    if let error = error {
                        print("發送音訊至 Gemini 失敗: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            print("音訊資料 JSON 序列化失敗: \(error)")
        }
    }

    // MARK: - 重連與 Keepalive

    private func scheduleReconnect() {
        guard !isIntentionalDisconnect else { return }

        stopPingTimer()
        isConnected = false

        guard reconnectAttempts < maxReconnectAttempts else {
            print("❌ 已達最大重連次數，停止嘗試")
            DispatchQueue.main.async {
                self.delegate?.didUpdateConnectionStatus("重連失敗，請手動重啟")
                self.delegate?.didPermanentlyDisconnect()
            }
            return
        }

        reconnectAttempts += 1
        // 指數退避：2s, 4s, 6s...，上限 30s
        let delay = min(Double(reconnectAttempts) * 2.0, 30.0)
        print("🔄 將在 \(delay) 秒後進行第 \(reconnectAttempts) 次重連")

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, !self.isIntentionalDisconnect else { return }
            self.performConnect()
        }
    }

    private func startPingTimer() {
        stopPingTimer()
        DispatchQueue.main.async { [weak self] in
            self?.pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                self?.sendPing()
            }
        }
    }

    private func stopPingTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.pingTimer?.invalidate()
            self?.pingTimer = nil
        }
    }

    private func sendPing() {
        guard isConnected else { return }
        webSocketTask?.sendPing { error in
            if let error = error {
                print("🏓 Ping 失敗: \(error.localizedDescription)")
            } else {
                print("🏓 Ping 成功")
            }
        }
    }

    // MARK: - 私有方法

    private func sendSetupConfig() {
        let isTranslateModel = modelName.contains("live-translate")

        var setupMessage: [String: Any] = [:]

        if isTranslateModel {
            setupMessage = [
                "setup": [
                    "model": "models/\(modelName)",
                    "inputAudioTranscription": [:],
                    "outputAudioTranscription": [:],
                    "generationConfig": [
                        "responseModalities": ["AUDIO"],
                        "translationConfig": [
                            "targetLanguageCode": "zh-TW",
                            "echoTargetLanguage": true
                        ]
                    ]
                ]
            ]
        } else {
            setupMessage = [
                "setup": [
                    "model": "models/\(modelName)",
                    "generationConfig": [
                        "responseModalities": ["AUDIO"]
                    ],
                    "systemInstruction": [
                        "parts": [
                            [
                                "text": "你是一個專業的即時口譯機器人。請聽取輸入的音訊（可能是英文、日文等各國語言），並將其即時、通順地翻譯成台灣繁體中文語音輸出。"
                            ]
                        ]
                    ]
                ]
            ]
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: setupMessage, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                let wsMessage = URLSessionWebSocketTask.Message.string(jsonString)
                webSocketTask?.send(wsMessage) { [weak self] error in
                    guard let self = self else { return }
                    if let error = error {
                        print("發送 Setup Config 失敗: \(error.localizedDescription)")
                        self.scheduleReconnect()
                    } else {
                        print("Live Setup Config 發送成功 (模型: \(self.modelName))")
                        self.isConnected = true
                        self.reconnectAttempts = 0
                        self.startPingTimer()
                        DispatchQueue.main.async { self.delegate?.didUpdateConnectionStatus("已連線 (即時翻譯中)") }
                    }
                }
            }
        } catch {
            print("建構 Setup Config 失敗: \(error)")
        }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    print("📩 收到伺服器訊息: \(text)")
                    self.parseServerResponse(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        print("📩 收到伺服器訊息 (Data): \(text)")
                        self.parseServerResponse(text)
                    }
                @unknown default:
                    break
                }
                self.receiveMessage()

            case .failure(let error):
                guard !self.isIntentionalDisconnect else { return }
                print("❌ 接收 WebSocket 失敗: \(error.localizedDescription)")
                self.scheduleReconnect()
            }
        }
    }

    private func parseServerResponse(_ jsonString: String) {
        guard let jsonData = jsonString.data(using: .utf8) else { return }

        do {
            guard let json = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else { return }

            // 處理 GoAway 信號：伺服器即將關閉，提前重連
            if let goAway = json["goAway"] as? [String: Any] {
                let timeLeft = goAway["timeLeft"] as? String ?? "未知"
                print("⚠️ 收到 GoAway 信號，伺服器將在 \(timeLeft) 後關閉連線，提前重連")
                DispatchQueue.main.async {
                    self.delegate?.didUpdateConnectionStatus("重新連線中... (Session 到期)")
                }
                scheduleReconnect()
                return
            }

            if let serverContent = json["serverContent"] as? [String: Any] {

                // 1. 取得會議原文字幕
                if let inputTranscription = serverContent["inputTranscription"] as? [String: Any],
                   let text = inputTranscription["text"] as? String, !text.isEmpty {
                    DispatchQueue.main.async {
                        self.delegate?.didReceiveInputTranscription(text)
                    }
                }

                // 2. 取得翻譯後繁中字幕
                if let outputTranscription = serverContent["outputTranscription"] as? [String: Any],
                   let text = outputTranscription["text"] as? String, !text.isEmpty {
                    DispatchQueue.main.async {
                        self.delegate?.didReceiveOutputTranscription(text)
                    }
                }

                // 3. 取得翻譯後語音 PCM 資料與通用模型文字
                if let modelTurn = serverContent["modelTurn"] as? [String: Any],
                   let parts = modelTurn["parts"] as? [[String: Any]] {

                    for part in parts {
                        if let inlineData = part["inlineData"] as? [String: Any],
                           let mimeType = inlineData["mimeType"] as? String, mimeType.hasPrefix("audio/pcm"),
                           let base64Audio = inlineData["data"] as? String,
                           let audioData = Data(base64Encoded: base64Audio) {

                            DispatchQueue.main.async {
                                self.delegate?.didReceiveAudioData(audioData)
                            }
                        }

                        if let text = part["text"] as? String, !text.isEmpty {
                            DispatchQueue.main.async {
                                self.delegate?.didReceiveOutputTranscription(text)
                            }
                        }
                    }
                }
            }
        } catch {
            print("解析 Gemini 伺服器回傳失敗: \(error)")
        }
    }
}

// MARK: - URLSessionWebSocketDelegate & URLSessionTaskDelegate

extension GeminiLiveConnection: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocolName: String?) {
        print("🟢 WebSocket 連線已成功開啟 (Protocol: \(protocolName ?? "無"))")
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        var reasonString = ""
        if let reason = reason {
            reasonString = String(data: reason, encoding: .utf8) ?? ""
        }
        print("❌ WebSocket 被 Gemini 伺服器關閉 (CloseCode: \(closeCode.rawValue), 原因: \(reasonString))")

        guard !isIntentionalDisconnect else { return }

        // CloseCode 1008 = Policy Violation：通常是模型名稱錯誤或 API Key 無效，屬於設定問題，不重連
        if closeCode.rawValue == 1008 {
            DispatchQueue.main.async {
                self.delegate?.didUpdateConnectionStatus("連線失敗：\(reasonString)")
                self.delegate?.didPermanentlyDisconnect()
            }
            return
        }

        scheduleReconnect()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error, !isIntentionalDisconnect else { return }
        print("❌ WebSocket 連線錯誤: \(error.localizedDescription)")
        scheduleReconnect()
    }
}
