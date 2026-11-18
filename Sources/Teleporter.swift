import Foundation
import AVFoundation
import HaishinKit

final class Teleporter: ObservableObject {
    private let connection = RTMPConnection()
    private var stream: RTMPStream?
    @Published var status = "Desligado"

    /// address: por exemplo rtmp://192.168.0.10/live
    /// key: nome do fluxo, por exemplo teleporter
    func start(address: String, key: String) {
        let stream = RTMPStream(connection: connection)
        self.stream = stream

        stream.attachAudio(AVCaptureDevice.default(for: .audio))
        stream.attachCamera(
            AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        )
        stream.videoSettings = VideoCodecSettings(
            videoSize: .init(width: 1280, height: 720),
            bitRate: 2_500_000
        )

        connection.connect(address)
        stream.publish(key)
        DispatchQueue.main.async { self.status = "Enviando para o PC" }
    }

    func stop() {
        stream?.close()
        connection.close()
        stream = nil
        DispatchQueue.main.async { self.status = "Desligado" }
    }
}
