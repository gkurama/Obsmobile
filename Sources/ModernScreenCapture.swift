import AVFoundation
import HaishinKit
import ScreenCaptureKit
import SwiftUI

@available(iOS 27.0, *)
@MainActor
final class ModernScreenCapture: NSObject, ObservableObject {
    @Published private(set) var isCapturing = false
    @Published private(set) var status = "Captura de ecrã parada"

    private let picker = SCContentSharingPicker.shared
    private var captureStream: SCStream?
    private var connection: RTMPConnection?
    private var rtmpStream: RTMPStream?
    nonisolated private let sampleRelay = RTMPSampleRelay()
    private var streamKey = ""

    func presentPicker() {
        picker.addObserver(self)
        picker.active = true
        var configuration = SCContentSharingPickerConfiguration()
        configuration.showsMicrophoneControl = true
        picker.defaultConfiguration = configuration
        picker.present()
    }

    func stop() {
        Task { await stopCapture() }
    }

    private func startCapture(with filter: SCContentFilter) async {
        await stopCapture()
        guard let defaults = UserDefaults(suiteName: "group.com.g.obsmobile.shared"),
              let url = defaults.string(forKey: "rtmpURL"),
              let key = defaults.string(forKey: "streamKey"),
              !key.isEmpty else {
            status = "Configure URL RTMP e chave no app"
            return
        }

        do {
            if filter.isMicrophoneEnabled {
                try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
                try AVAudioSession.sharedInstance().setActive(true)
            }
            let connection = RTMPConnection()
            let output = RTMPStream(connection: connection)
            output.isMultiTrackAudioMixingEnabled = true
            output.audioMixerSettings.tracks[1] = .default
            output.audioMixerSettings.tracks[0] = .default
            output.videoSettings = VideoCodecSettings(videoSize: CGSize(width: 1280, height: 720), bitRate: 2_500_000)
            output.videoMixerSettings.mode = .passthrough
            self.connection = connection
            self.rtmpStream = output
            sampleRelay.stream = output
            self.streamKey = key
            connection.addEventListener(.rtmpStatus, selector: #selector(handleRTMPStatus(_:)), observer: self)
            connection.connect(url, arguments: nil)

            var configuration = SCStreamConfiguration()
            configuration.width = 1280
            configuration.height = 720
            configuration.queueDepth = 5
            configuration.capturesAudio = true
            configuration.sampleRate = 44_100
            configuration.channelCount = 2

            let newStream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.g.obsmobile.screencapture.video"))
            try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.g.obsmobile.screencapture.audio"))
            if filter.isMicrophoneEnabled {
                try newStream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: DispatchQueue(label: "com.g.obsmobile.screencapture.mic"))
            }

            let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.g.obsmobile.shared")!
            let folder = container.appendingPathComponent("ScreenBroadcasts", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let recordingURL = folder.appendingPathComponent("screen-\(Int(Date().timeIntervalSince1970)).mp4")
            let recordingConfiguration = SCRecordingOutputConfiguration()
            recordingConfiguration.outputURL = recordingURL
            let recordingOutput = SCRecordingOutput(configuration: recordingConfiguration, delegate: self)
            try newStream.addRecordingOutput(recordingOutput)

            try await newStream.startCapture()
            captureStream = newStream
            UserDefaults(suiteName: "group.com.g.obsmobile.shared")?.set(true, forKey: "screenCaptureActive")
            isCapturing = true
            status = "Capturando e transmitindo o ecrã"
        } catch {
            status = "Falha ao iniciar captura: \(error.localizedDescription)"
            await stopCapture()
        }
    }

    private func stopCapture() async {
        if let captureStream {
            do { try await captureStream.stopCapture() }
            catch { status = "Erro ao parar captura: \(error.localizedDescription)" }
        }
        captureStream = nil
        UserDefaults(suiteName: "group.com.g.obsmobile.shared")?.set(false, forKey: "screenCaptureActive")
        sampleRelay.stream = nil
        rtmpStream?.close()
        connection?.close()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        rtmpStream = nil
        connection = nil
        isCapturing = false
        if status == "Capturando e transmitindo o ecrã" { status = "Captura de ecrã parada" }
    }

    @objc private func handleRTMPStatus(_ notification: Notification) {
        guard let data = Event.from(notification).data as? ASObject,
              let code = data["code"] as? String else { return }
        if code == RTMPConnection.Code.connectSuccess.rawValue {
            rtmpStream?.publish(streamKey)
        } else if code == RTMPConnection.Code.connectFailed.rawValue {
            status = "Falha na conexão RTMP"
        }
    }
}

@available(iOS 27.0, *)
extension ModernScreenCapture: SCContentSharingPickerObserver {
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in await self.startCapture(with: filter) }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in self.stop() }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        Task { @MainActor in self.status = "Não foi possível abrir o seletor: \(error.localizedDescription)" }
    }
}

@available(iOS 27.0, *)
extension ModernScreenCapture: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        let defaults = UserDefaults(suiteName: "group.com.g.obsmobile.shared")
        let appVolume = Float(min(max(defaults?.double(forKey: "audioVolume.appAudio") ?? 0.8, 0), 1))
        let micVolume = Float(min(max(defaults?.double(forKey: "audioVolume.microphone") ?? 0.8, 0), 1))
        self.sampleRelay.append(sampleBuffer, type: type, appVolume: appVolume, microphoneVolume: micVolume)
    }
}

@available(iOS 27.0, *)
private final class RTMPSampleRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var _stream: RTMPStream?
    var stream: RTMPStream? {
        get { lock.lock(); defer { lock.unlock() }; return _stream }
        set { lock.lock(); defer { lock.unlock() }; _stream = newValue }
    }

    func append(_ sampleBuffer: CMSampleBuffer, type: SCStreamOutputType, appVolume: Float, microphoneVolume: Float) {
        lock.lock()
        defer { lock.unlock() }
        guard let stream = _stream else { return }
        switch type {
        case .screen: stream.append(sampleBuffer)
        case .audio:
            stream.audioMixerSettings.tracks[1]?.volume = appVolume
            stream.append(sampleBuffer, track: 1)
        case .microphone:
            stream.audioMixerSettings.tracks[0]?.volume = microphoneVolume
            stream.append(sampleBuffer, track: 0)
        @unknown default: break
        }
    }
}

@available(iOS 27.0, *)
extension ModernScreenCapture: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor in
            self.sampleRelay.stream = nil
            self.rtmpStream?.close()
            self.connection?.close()
            self.rtmpStream = nil
            self.connection = nil
            self.captureStream = nil
            UserDefaults(suiteName: "group.com.g.obsmobile.shared")?.set(false, forKey: "screenCaptureActive")
            self.status = "Captura parada: \(error.localizedDescription)"
            self.isCapturing = false
        }
    }
}

@available(iOS 27.0, *)
extension ModernScreenCapture: SCRecordingOutputDelegate {
    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.status = "Gravação do ecrã concluída" }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        Task { @MainActor in self.status = "Erro na gravação do ecrã: \(error.localizedDescription)" }
    }
}

@available(iOS 27.0, *)
struct ModernScreenCaptureControl: View {
    let prepareForCapture: (() -> Void) -> Void
    @StateObject private var capture = ModernScreenCapture()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(capture.isCapturing ? "Parar captura de ecrã" : "Transmitir e gravar ecrã") {
                if capture.isCapturing { capture.stop() }
                else { prepareForCapture { capture.presentPicker() } }
            }
            Text(capture.status).font(.caption2).foregroundColor(.secondary)
        }
    }
}
