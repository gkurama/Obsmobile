import HaishinKit
import SwiftUI

@MainActor
final class RTMPMonitor: ObservableObject {
    @Published private(set) var stream: RTMPStream?
    @Published private(set) var status = "Monitor desligado"

    private var connection: RTMPConnection?
    private var streamKey = ""

    func play(address: String, key: String) {
        stop()
        guard let components = URLComponents(string: address),
              ["rtmp", "rtmps"].contains(components.scheme?.lowercased() ?? ""),
              components.host != nil,
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "Informe URL RTMP e chave válidas"
            return
        }
        streamKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let connection = RTMPConnection()
        let stream = RTMPStream(connection: connection)
        self.connection = connection
        self.stream = stream
        connection.addEventListener(.rtmpStatus, selector: #selector(handleStatus(_:)), observer: self)
        connection.connect(address, arguments: nil)
        status = "Conectando ao sinal do PC…"
    }

    func stop() {
        stream?.close()
        connection?.close()
        stream = nil
        connection = nil
        status = "Monitor desligado"
    }

    @objc private func handleStatus(_ notification: Notification) {
        guard let data = Event.from(notification).data as? ASObject,
              let code = data["code"] as? String else { return }
        if code == RTMPConnection.Code.connectSuccess.rawValue {
            stream?.play(streamKey)
            status = "Recebendo sinal do PC"
        } else if code == RTMPConnection.Code.connectFailed.rawValue {
            status = "Não foi possível conectar ao sinal do PC"
        }
    }
}

struct RTMPVideoMonitor: UIViewRepresentable {
    @ObservedObject var monitor: RTMPMonitor

    func makeUIView(context: Context) -> MTHKView {
        let view = MTHKView(frame: .zero)
        view.videoGravity = .resizeAspect
        view.backgroundColor = .black
        view.attachStream(monitor.stream)
        return view
    }

    func updateUIView(_ view: MTHKView, context: Context) {
        view.attachStream(monitor.stream)
    }
}
