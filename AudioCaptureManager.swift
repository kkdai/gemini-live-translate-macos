import Foundation
import ScreenCaptureKit
import AVFoundation

protocol AudioCaptureDelegate: AnyObject {
    func didCaptureAudioData(_ data: Data)
    func didUpdateApplications(_ apps: [SCRunningApplication])
}

class AudioCaptureManager: NSObject, SCStreamOutput {
    weak var delegate: AudioCaptureDelegate?
    
    private var stream: SCStream?
    private var isCapturing = false
    
    // 音訊重採樣設定 (Gemini Live API 需要 16kHz 或 24kHz, 16-bit PCM, 單聲道)
    private let targetSampleRate: Double = 16000.0
    private let targetChannels: AVAudioChannelCount = 1
    
    private var audioConverter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private lazy var targetFormat: AVAudioFormat = {
        return AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: targetSampleRate, channels: targetChannels, interleaved: false)!
    }()

    /// 獲取目前系統中所有運行且有音訊輸出的應用程式
    /// - Returns: (apps, errorMessage) — errorMessage 非 nil 表示權限被拒或發生錯誤
    func fetchShareableApps() async -> (apps: [SCRunningApplication], error: String?) {
        do {
            let content = try await SCShareableContent.current
            let apps = content.applications.filter { app in
                let name = app.applicationName
                guard !name.isEmpty else { return false }
                let bundleId = app.bundleIdentifier
                return !bundleId.hasPrefix("com.apple.system") && bundleId != Bundle.main.bundleIdentifier
            }.sorted { $0.applicationName < $1.applicationName }
            return (apps, nil)
        } catch {
            let nsError = error as NSError
            print("fetchShareableApps 失敗 — domain: \(nsError.domain), code: \(nsError.code), desc: \(error.localizedDescription)")
            // SCStreamError.userDeclined = -3801
            let isPermissionDenied = nsError.code == -3801
            let message = isPermissionDenied
                ? "需要螢幕錄製權限：請至「系統設定 > 隱私權與安全性 > 螢幕錄製」開啟授權"
                : "無法取得 App 清單（code \(nsError.code)）：\(error.localizedDescription)"
            return ([], message)
        }
    }

    /// 開始錄製指定應用程式的音訊
    func startCapture(for app: SCRunningApplication) async {
        guard !isCapturing else { return }
        
        do {
            let content = try await SCShareableContent.current
            
            guard let targetApp = content.applications.first(where: { $0.processID == app.processID }) else {
                print("找不到目標應用程式")
                return
            }
            
            let appFilter = SCContentFilter(display: content.displays.first!, including: [targetApp], exceptingWindows: [])
            
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.width = 32
            config.height = 32
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            
            stream = SCStream(filter: appFilter, configuration: config, delegate: nil)
            try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.translator.audioQueue"))
            
            try await stream?.startCapture()
            isCapturing = true
            print("已啟動應用程式 [\(app.applicationName)] 的音訊擷取")
        } catch {
            print("啟動擷取失敗: \(error.localizedDescription)")
        }
    }

    /// 停止錄製
    func stopCapture() async {
        guard isCapturing else { return }
        
        do {
            try await stream?.stopCapture()
            stream = nil
            isCapturing = false
            audioConverter = nil
            sourceFormat = nil
            print("音訊擷取已停止")
        } catch {
            print("停止擷取失敗: \(error.localizedDescription)")
        }
    }

    // MARK: - SCStreamOutput 代理方法
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard sampleBuffer.isValid else { return }
        
        // 1. 取得音訊格式資訊
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee else {
            return
        }
        
        // 2. 初始化重採樣轉換器
        setupConverterIfNeeded(sourceASBD: asbd)
        
        // 3. 將 CMSampleBuffer 轉換為 AVAudioPCMBuffer
        guard let sourceBuffer = audioBufferFromSampleBuffer(sampleBuffer, asbd: asbd) else { return }
        
        // 4. 重採樣為 Gemini Live 支援的 16kHz PCM
        guard let converter = audioConverter else { return }
        
        let frameCount = AVAudioFrameCount(Double(sourceBuffer.frameLength) * (targetSampleRate / asbd.mSampleRate))
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }
        
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return sourceBuffer
        }
        
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if let err = error {
            print("音訊轉換出錯: \(err.localizedDescription)")
            return
        }
        
        // 5. 提取二進位資料 (Int16)
        if let channelData = outputBuffer.int16ChannelData {
            let dataSize = Int(outputBuffer.frameLength) * 2 // 16-bit = 2 bytes per sample
            let rawPointer = UnsafeRawPointer(channelData.pointee)
            let audioData = Data(bytes: rawPointer, count: dataSize)
            
            // 6. 傳遞給代理
            delegate?.didCaptureAudioData(audioData)
        }
    }
    
    private func setupConverterIfNeeded(sourceASBD: AudioStreamBasicDescription) {
        guard sourceFormat == nil else { return }
        
        var tempASBD = AudioStreamBasicDescription(
            mSampleRate: sourceASBD.mSampleRate,
            mFormatID: sourceASBD.mFormatID,
            mFormatFlags: sourceASBD.mFormatFlags,
            mBytesPerPacket: sourceASBD.mBytesPerPacket,
            mFramesPerPacket: sourceASBD.mFramesPerPacket,
            mBytesPerFrame: sourceASBD.mBytesPerFrame,
            mChannelsPerFrame: sourceASBD.mChannelsPerFrame,
            mBitsPerChannel: sourceASBD.mBitsPerChannel,
            mReserved: 0
        )
        
        sourceFormat = AVAudioFormat(streamDescription: &tempASBD)
        
        if let sourceFormat = sourceFormat {
            audioConverter = AVAudioConverter(from: sourceFormat, to: targetFormat)
            print("初始化音訊重採樣器成功: \(sourceASBD.mSampleRate)Hz -> \(targetSampleRate)Hz")
        }
    }
    
    /// 核心安全轉換：動態分配記憶體空間以支援立體聲或多聲道 (避免 Copy 失敗為 0)
    private func audioBufferFromSampleBuffer(_ sampleBuffer: CMSampleBuffer, asbd: AudioStreamBasicDescription) -> AVAudioPCMBuffer? {
        guard let sourceFormat = sourceFormat else { return nil }
        
        // 1. 動態獲取所需要的 AudioBufferList 記憶體大小
        var bufferListSize = 0
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        
        guard status == noErr else {
            print("❌ 無法獲取 AudioBufferList 記憶體大小: \(status)")
            return nil
        }
        
        // 2. 分配足夠空間的指標並填充
        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: bufferListSize)
        defer { bufferListPointer.deallocate() }
        
        var blockBuffer: CMBlockBuffer?
        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: bufferListPointer,
            bufferListSize: bufferListSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        guard status == noErr else {
            print("❌ 無法填充 AudioBufferList: \(status)")
            return nil
        }
        
        // 3. 建立符合來源格式的 AVAudioPCMBuffer
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else { return nil }
        pcmBuffer.frameLength = frameCount
        
        // 4. 安全地進行音訊資料拷貝
        let audioBuffers = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        
        for (index, audioBuffer) in audioBuffers.enumerated() {
            guard let mData = audioBuffer.mData, index < Int(sourceFormat.channelCount) else { continue }
            
            let isNonInterleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
            let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
            
            if isFloat {
                if isNonInterleaved {
                    if let dst = pcmBuffer.floatChannelData?[index] {
                        memcpy(dst, mData, Int(audioBuffer.mDataByteSize))
                    }
                } else {
                    if let dst = pcmBuffer.floatChannelData?[0] {
                        let offset = index * Int(frameCount)
                        memcpy(dst.advanced(by: offset), mData, Int(audioBuffer.mDataByteSize))
                    }
                }
            } else {
                if isNonInterleaved {
                    if let dst = pcmBuffer.int16ChannelData?[index] {
                        memcpy(dst, mData, Int(audioBuffer.mDataByteSize))
                    }
                } else {
                    if let dst = pcmBuffer.int16ChannelData?[0] {
                        let offset = index * Int(frameCount)
                        memcpy(dst.advanced(by: offset), mData, Int(audioBuffer.mDataByteSize))
                    }
                }
            }
        }
        
        return pcmBuffer
    }
}
