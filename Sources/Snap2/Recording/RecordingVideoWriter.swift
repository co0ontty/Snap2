import AVFoundation
import CoreMedia
import Foundation

/// 把 SCStream 吐出来的 CMSampleBuffer 写成 MP4 (H.264 + AAC) 文件。
///
/// 设计要点：
/// - **首帧 PTS 决定 startSession 锚点**：SCStream 第一帧的 presentationTimeStamp 不为 0，
///   直接传给 `startSession(atSourceTime:)`，否则 AVAssetWriter 会把所有帧都偏移到 0
///   导致首段画面被丢弃。
/// - **video & audio 各自一个 AVAssetWriterInput**：`expectsMediaDataInRealTime = true`
///   告诉 writer 别囤帧、宁可丢也别等——录屏属实时管线，掉一两帧好过整段卡顿。
/// - **P3 元数据写进 video output settings**：与 SCStream 抓的 Display P3 像素源头对齐，
///   QuickTime / Chrome / iMovie 解码时按 P3 显示，避免饱和色被当 sRGB 解释而偏暗
///   （和截图链路同源问题）。
/// - **finish 异步回调**：`finishWriting` 是异步的，外部要等真正写盘完成再决定 toast/openInFinder。
///
/// 线程模型：所有 append 都从 SCStream 的输出队列上来，串行；start/finish 在主线程调用，
/// 通过 writer 自身的串行化保证状态安全。
final class RecordingVideoWriter {

    enum WriterError: Error {
        case alreadyStarted
        case notReady(String)
        case finishedWithoutFrames
        case underlying(Error)
    }

    /// 输出文件 URL（始终是 .mp4）
    let outputURL: URL

    private let assetWriter: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?
    /// 用 BGRA 像素直接 append 时，pixelBufferAdaptor 不是必须的；我们让 writer 内部封装。
    private var didStartSession = false
    private var firstVideoPTS: CMTime?
    private var lastVideoPTS: CMTime?
    private var droppedVideoCount = 0
    private var droppedAudioCount = 0

    /// 创建 writer。
    /// - Parameters:
    ///   - outputURL: 目标 .mp4 文件路径
    ///   - pixelWidth/Height: SCStream 配置的 width/height（像素，含 backingScale）
    ///   - includesAudio: 是否预创建 audio input。false 时 SCStream 不开音频，writer 也省一路 input。
    init(outputURL: URL, pixelWidth: Int, pixelHeight: Int, includesAudio: Bool) throws {
        self.outputURL = outputURL

        // 同名残留先清掉，否则 AVAssetWriter 会报 .fileFormatNotRecognized 之类的莫名错误
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        assetWriter.shouldOptimizeForNetworkUse = false

        // —— Video input ——
        // 比特率按像素面积粗略估算：每像素 0.1 bps × 30fps ≈ 3 bps/pixel/frame；
        // 1920×1080@30 ≈ 6 Mbps，4K@30 ≈ 24 Mbps。够用，文件不会爆。
        let bitRate = max(2_000_000, Int(Double(pixelWidth * pixelHeight) * 3.0))

        var videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: pixelWidth,
            AVVideoHeightKey: pixelHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 60,  // 关键帧 ≈ 2s @30fps，便于剪辑/搜索
                AVVideoAllowFrameReorderingKey: true,
            ],
        ]
        // P3 色彩元数据：与 SCStream 配置的 displayP3 对齐（rec.709 transfer + matrix，P3 D65 primaries
        // 是 macOS 屏录约定俗成的写法——HDR/P3 视频用 ITU-R 709 transfer 是 Apple 自己的规范）。
        videoSettings[AVVideoColorPropertiesKey] = [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_P3_D65,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        guard assetWriter.canAdd(videoInput) else {
            throw WriterError.notReady("AVAssetWriter 不接受 video input")
        }
        assetWriter.add(videoInput)

        // —— Audio input ——
        if includesAudio {
            // SCStream 默认输出 48kHz Float32 stereo interleaved。我们让 AVAssetWriter 内部转 AAC，
            // 这条路径在 macOS 14 上稳定，无需手工挂 AVAudioConverter。
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 48_000,
                AVEncoderBitRateKey: 128_000,
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            guard assetWriter.canAdd(input) else {
                throw WriterError.notReady("AVAssetWriter 不接受 audio input")
            }
            assetWriter.add(input)
            audioInput = input
        } else {
            audioInput = nil
        }
    }

    /// 让 writer 进入 writing 状态。startSession 推迟到拿到第一帧时做（首帧 PTS 即起点）。
    func startWriting() throws {
        guard !didStartSession, assetWriter.status == .unknown else {
            throw WriterError.alreadyStarted
        }
        guard assetWriter.startWriting() else {
            throw WriterError.underlying(assetWriter.error ?? NSError(domain: "RecordingVideoWriter",
                                                                       code: -1,
                                                                       userInfo: [NSLocalizedDescriptionKey: "startWriting 返回 false"]))
        }
    }

    /// 吃一个 video sample。第一次进来会做 startSession。
    /// 注意：调用方负责确保 sampleBuffer 是 valid（CMSampleBufferDataIsReady & 状态正常）。
    func append(videoBuffer sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard assetWriter.status == .writing else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if !didStartSession {
            assetWriter.startSession(atSourceTime: pts)
            didStartSession = true
            firstVideoPTS = pts
        }

        if videoInput.isReadyForMoreMediaData {
            videoInput.append(sampleBuffer)
            lastVideoPTS = pts
        } else {
            droppedVideoCount &+= 1
        }
    }

    /// 吃一个 audio sample。如果 audioInput 不存在或还没 startSession，丢弃。
    func append(audioBuffer sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard let input = audioInput else { return }
        guard didStartSession, assetWriter.status == .writing else {
            // session 还没起，丢弃这段 audio——session 一旦由 video 起来，后续 audio 才有锚点
            droppedAudioCount &+= 1
            return
        }
        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        } else {
            droppedAudioCount &+= 1
        }
    }

    /// 收尾：endSession + markAsFinished + finishWriting 异步回调。
    /// completion 在主线程派发。
    func finish(_ completion: @escaping (Result<URL, WriterError>) -> Void) {
        // 没拿到一帧 → 没有 session，直接当失败处理（输出文件可能是 0 字节）
        guard didStartSession else {
            completion(.failure(.finishedWithoutFrames))
            return
        }
        if let last = lastVideoPTS {
            assetWriter.endSession(atSourceTime: last)
        }
        videoInput.markAsFinished()
        audioInput?.markAsFinished()

        assetWriter.finishWriting { [outputURL, weak self] in
            let outcome: Result<URL, WriterError>
            if let err = self?.assetWriter.error {
                outcome = .failure(.underlying(err))
            } else {
                outcome = .success(outputURL)
            }
            if let dropped = self?.droppedVideoCount, dropped > 0 {
                NSLog("[RecordingVideoWriter] 录屏期间丢弃 \(dropped) 个 video buffer")
            }
            if let droppedA = self?.droppedAudioCount, droppedA > 0 {
                NSLog("[RecordingVideoWriter] 录屏期间丢弃 \(droppedA) 个 audio buffer")
            }
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    /// 取消：finish 但删文件。用于 startWriting 失败 / 用户 Esc 强制丢弃的清理。
    func cancel() {
        if assetWriter.status == .writing {
            assetWriter.cancelWriting()
        }
        try? FileManager.default.removeItem(at: outputURL)
    }
}
