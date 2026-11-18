import Foundation
import AVFoundation
import HaishinKit
import SwiftUI
import UIKit

final class Teleporter: ObservableObject {
    private lazy var connection: RTMPConnection = {
        let value = RTMPConnection()
        value.addEventListener(.rtmpStatus, selector: #selector(handleStatus(_:)), observer: self)
        return value
    }()
    private var stream: RTMPStream?
    private var streamKey = ""
    private var screenObjects: [ScreenObject] = []
    @Published var status = "Desligado"

    /// address: por exemplo rtmp://192.168.0.10/live
    /// key: nome do fluxo, por exemplo teleporter
    func start(address: String, key: String, cameraPosition: AVCaptureDevice.Position, scene: StudioScene) {
        guard let components = URLComponents(string: address),
              ["rtmp", "rtmps"].contains(components.scheme?.lowercased() ?? ""),
              components.host != nil,
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            DispatchQueue.main.async { self.status = "Informe uma URL RTMP e uma chave válidas" }
            return
        }
        streamKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let stream = RTMPStream(connection: connection)
        self.stream = stream
        stream.isMultiTrackAudioMixingEnabled = true
        stream.audioMixerSettings.tracks[0] = .default
        let audioDefaults = UserDefaults(suiteName: "group.com.g.obsmobile.shared")
        if audioDefaults?.object(forKey: "audioVolume.microphone") != nil {
            stream.audioMixerSettings.tracks[0]?.volume = Float(audioDefaults?.double(forKey: "audioVolume.microphone") ?? 0)
        }

        stream.attachAudio(AVCaptureDevice.default(for: .audio))
        stream.attachCamera(
            AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition)
        )
        stream.videoSettings = VideoCodecSettings(
            videoSize: .init(width: 1280, height: 720),
            bitRate: 2_500_000
        )
        stream.videoMixerSettings.mode = .offscreen
        stream.screen.size = CGSize(width: 1280, height: 720)
        configureScene(scene)
        stream.screen.startRunning()

        DispatchQueue.main.async { self.status = "Conectando ao servidor RTMP…" }
        connection.connect(address, arguments: nil)
    }

    func stop() {
        stream?.screen.stopRunning()
        stream?.close()
        connection.close()
        stream = nil
        DispatchQueue.main.async { self.status = "Desligado" }
    }

    func updateScene(_ scene: StudioScene) {
        guard stream != nil else { return }
        configureScene(scene)
    }

    private func configureScene(_ scene: StudioScene) {
        guard let stream else { return }
        for object in screenObjects { stream.screen.removeChild(object) }
        screenObjects.removeAll()

        for source in scene.sources where source.visible {
            let object: ScreenObject
            let width: CGFloat
            let height: CGFloat
            switch source.kind {
            case .camera:
                let video = VideoTrackScreenObject()
                video.track = 0
                video.videoGravity = .resizeAspectFill
                object = video
                width = 1280
                height = 720
            case .text:
                let text = TextScreenObject()
                text.string = source.text
                text.attributes = [
                    .font: UIFont.boldSystemFont(ofSize: 44),
                    .foregroundColor: UIColor.white,
                    .backgroundColor: UIColor.black.withAlphaComponent(0.45),
                ]
                object = text
                width = 600 * source.scale
                height = 100 * source.scale
            case .color:
                let color = ImageScreenObject()
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 180))
                color.cgImage = renderer.image { context in
                    UIColor(source.color).setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
                }.cgImage
                object = color
                width = 240 * source.scale
                height = 135 * source.scale
            case .image:
                guard let data = source.imageData, let image = UIImage(data: data), let cgImage = image.cgImage else { continue }
                let picture = ImageScreenObject()
                picture.cgImage = cgImage
                object = picture
                width = 320 * source.scale
                height = 240 * source.scale
            }

            object.size = CGSize(width: width, height: height)
            object.horizontalAlignment = .left
            object.verticalAlignment = .top
            if source.kind == .camera {
                object.layoutMargin = .init(top: 0, left: 0, bottom: 0, right: 0)
            } else {
                let left = min(max(0, source.x * 1280 - width / 2), 1280 - width)
                let top = min(max(0, source.y * 720 - height / 2), 720 - height)
                object.layoutMargin = .init(top: top, left: left, bottom: 0, right: 0)
            }
            do {
                try stream.screen.addChild(object)
                screenObjects.append(object)
            } catch {
                DispatchQueue.main.async { self.status = "Não foi possível montar a cena" }
            }
        }
    }

    @objc private func handleStatus(_ notification: Notification) {
        guard let data = Event.from(notification).data as? ASObject,
              let code = data["code"] as? String else { return }
        switch code {
        case RTMPConnection.Code.connectSuccess.rawValue:
            stream?.publish(streamKey)
            DispatchQueue.main.async { self.status = "Conectado ao servidor RTMP" }
        case RTMPConnection.Code.connectFailed.rawValue:
            DispatchQueue.main.async { self.status = "Falha na conexão RTMP" }
        default:
            break
        }
    }
}
