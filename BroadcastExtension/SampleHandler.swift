import HaishinKit
import AVFoundation
import ReplayKit
import VideoToolbox

/// Receives the system-wide iPhone screen and audio buffers from ReplayKit and
/// publishes them to the RTMP destination shared by the host app.
final class SampleHandler: RPBroadcastSampleHandler {
    private let settings = UserDefaults(suiteName: "group.com.g.obsmobile.shared")
    private var needsVideoConfiguration = true
    private var rotator: VideoRotator?
    private var assetWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?

    private lazy var connection: RTMPConnection = {
        let value = RTMPConnection()
        value.addEventListener(.rtmpStatus, selector: #selector(handleRTMPStatus(_:)), observer: self)
        value.addEventListener(.ioError, selector: #selector(handleRTMPError(_:)), observer: self)
        return value
    }()

    private lazy var stream: RTMPStream = {
        let value = RTMPStream(connection: connection)
        value.isMultiTrackAudioMixingEnabled = true
        value.audioMixerSettings.tracks[1] = .default
        value.videoSettings.scalingMode = .letterbox
        return value
    }()

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard let url = settings?.string(forKey: "rtmpURL"),
              let key = settings?.string(forKey: "streamKey"),
              !key.isEmpty,
              let parts = URLComponents(string: url),
              ["rtmp", "rtmps"].contains(parts.scheme?.lowercased() ?? ""),
              parts.host != nil else {
            finishBroadcastWithError(NSError(
                domain: "OBSMobile.Broadcast",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Configure uma URL RTMP e uma chave de transmissão no app antes de iniciar a captura."]
            ))
            return
        }

        settings?.set(true, forKey: "screenCaptureActive")
        rotator = VideoRotator()
        connection.connect(url, arguments: nil)
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .video:
            appendVideoToRecording(sampleBuffer)
            if needsVideoConfiguration, let dimensions = sampleBuffer.formatDescription?.dimensions {
                stream.videoSettings.videoSize = CGSize(width: CGFloat(dimensions.width), height: CGFloat(dimensions.height))
                stream.videoSettings.profileLevel = kVTProfileLevel_H264_Baseline_AutoLevel as String
                needsVideoConfiguration = false
            }
            if let rotator {
                switch rotator.rotate(buffer: sampleBuffer) {
                case .success(let rotated): stream.append(rotated)
                case .failure: stream.append(sampleBuffer)
                }
            } else {
                stream.append(sampleBuffer)
            }
        case .audioMic:
            guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
            appendAudioToRecording(sampleBuffer)
            stream.audioMixerSettings.tracks[0]?.volume = audioVolume(forKey: "microphone")
            stream.append(sampleBuffer, track: 0)
        case .audioApp:
            guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
            appendAudioToRecording(sampleBuffer)
            stream.audioMixerSettings.tracks[1]?.volume = audioVolume(forKey: "appAudio")
            stream.append(sampleBuffer, track: 1)
        @unknown default:
            break
        }
    }

    override func broadcastPaused() {}

    override func broadcastResumed() {}

    override func broadcastFinished() {
        settings?.set(false, forKey: "screenCaptureActive")
        stream.close()
        connection.close()
        finishScreenRecording()
    }

    @objc private func handleRTMPStatus(_ notification: Notification) {
        guard let data = Event.from(notification).data as? ASObject,
              let code = data["code"] as? String else { return }
        if code == RTMPConnection.Code.connectSuccess.rawValue {
            guard let key = settings?.string(forKey: "streamKey"), !key.isEmpty else { return }
            stream.publish(key)
        } else if code == RTMPConnection.Code.connectFailed.rawValue {
            settings?.set(false, forKey: "screenCaptureActive")
            finishBroadcastWithError(NSError(
                domain: "OBSMobile.Broadcast",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Falha ao conectar ao servidor RTMP. Verifique a URL, a chave e a rede."]
            ))
        }
    }

    @objc private func handleRTMPError(_ notification: Notification) {
        settings?.set(false, forKey: "screenCaptureActive")
        finishBroadcastWithError(NSError(
            domain: "OBSMobile.Broadcast",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "A conexão RTMP foi interrompida."]
        ))
    }

    private func audioVolume(forKey key: String) -> Float {
        let settingKey = "audioVolume.\(key)"
        guard settings?.object(forKey: settingKey) != nil else { return 0.8 }
        return Float(min(max(settings?.double(forKey: settingKey) ?? 0, 0), 1))
    }

    private func appendVideoToRecording(_ sampleBuffer: CMSampleBuffer) {
        if assetWriter == nil { createScreenRecording(for: sampleBuffer) }
        guard let input = videoWriterInput,
              assetWriter?.status == .writing,
              input.isReadyForMoreMediaData else { return }
        _ = input.append(sampleBuffer)
    }

    private func appendAudioToRecording(_ sampleBuffer: CMSampleBuffer) {
        guard let input = audioWriterInput,
              assetWriter?.status == .writing,
              input.isReadyForMoreMediaData else { return }
        _ = input.append(sampleBuffer)
    }

    private func createScreenRecording(for sampleBuffer: CMSampleBuffer) {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.g.obsmobile.shared"),
              let dimensions = sampleBuffer.formatDescription?.dimensions else { return }
        let folder = container.appendingPathComponent("ScreenBroadcasts", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("screen-\(Int(Date().timeIntervalSince1970)).mov")
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: dimensions.width,
                AVVideoHeightKey: dimensions.height,
            ])
            videoInput.expectsMediaDataInRealTime = true
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000,
            ])
            audioInput.expectsMediaDataInRealTime = true
            guard writer.canAdd(videoInput) else { return }
            writer.add(videoInput)
            if writer.canAdd(audioInput) { writer.add(audioInput); audioWriterInput = audioInput }
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            assetWriter = writer
            videoWriterInput = videoInput
        } catch {
            assetWriter = nil
        }
    }

    private func finishScreenRecording() {
        videoWriterInput?.markAsFinished()
        audioWriterInput?.markAsFinished()
        assetWriter?.finishWriting { [weak self] in
            self?.assetWriter = nil
            self?.videoWriterInput = nil
            self?.audioWriterInput = nil
        }
    }
}
