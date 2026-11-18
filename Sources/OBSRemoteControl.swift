import Combine
import CryptoKit
import Foundation

@MainActor
final class OBSRemoteControl: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var status = "Desconectado"
    @Published private(set) var scenes: [String] = []
    @Published private(set) var currentScene = ""

    private var socket: URLSessionWebSocketTask?
    private var password = ""
    private var receiveTask: Task<Void, Never>?

    func connect(address: String, password: String) {
        disconnect()
        guard let url = URL(string: address), ["ws", "wss"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            status = "Use um endereço ws:// ou wss:// válido"
            return
        }
        self.password = password
        status = "Conectando ao OBS…"
        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()
        receiveTask = Task { [weak self] in await self?.receiveMessages() }
    }

    func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        isConnected = false
        scenes = []
        currentScene = ""
        status = "Desconectado"
    }

    func selectScene(_ name: String) {
        sendRequest("SetCurrentProgramScene", data: ["sceneName": name])
    }

    func startStreaming() { sendRequest("StartStream") }
    func stopStreaming() { sendRequest("StopStream") }

    func updateTextInput(named name: String, text: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sendRequest("SetInputSettings", data: [
            "inputName": trimmed,
            "inputSettings": ["text": text],
            "overlay": true,
        ])
    }

    private func receiveMessages() async {
        guard let socket else { return }
        do {
            while !Task.isCancelled {
                let message = try await socket.receive()
                guard case .string(let text) = message,
                      let data = text.data(using: .utf8),
                      let packet = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let op = packet["op"] as? Int,
                      let body = packet["d"] as? [String: Any] else { continue }
                await handle(op: op, data: body)
            }
        } catch {
            isConnected = false
            status = "OBS desconectado: \(error.localizedDescription)"
        }
    }

    private func handle(op: Int, data: [String: Any]) async {
        switch op {
        case 0:
            let rpcVersion = data["rpcVersion"] as? Int ?? 1
            var identify: [String: Any] = ["rpcVersion": rpcVersion, "eventSubscriptions": 5]
            if let auth = data["authentication"] as? [String: String],
               let salt = auth["salt"], let challenge = auth["challenge"] {
                let secretHash = SHA256.hash(data: Data((password + salt).utf8))
                let secret = Data(secretHash).base64EncodedString()
                let authHash = SHA256.hash(data: Data((secret + challenge).utf8))
                identify["authentication"] = Data(authHash).base64EncodedString()
            }
            send(["op": 1, "d": identify])
        case 2:
            isConnected = true
            status = "Conectado ao OBS"
            sendRequest("GetSceneList")
        case 5:
            handleEvent(data)
        case 7:
            handleResponse(data)
        case 9:
            status = "O OBS recusou a conexão WebSocket"
            isConnected = false
        default:
            break
        }
    }

    private func handleEvent(_ data: [String: Any]) {
        guard let event = data["eventType"] as? String,
              let eventData = data["eventData"] as? [String: Any] else { return }
        switch event {
        case "CurrentProgramSceneChanged":
            currentScene = eventData["sceneName"] as? String ?? currentScene
        case "SceneListChanged":
            sendRequest("GetSceneList")
        default:
            break
        }
    }

    private func handleResponse(_ data: [String: Any]) {
        guard let responseType = data["requestType"] as? String,
              responseType == "GetSceneList",
              let responseData = data["responseData"] as? [String: Any] else { return }
        scenes = (responseData["scenes"] as? [[String: Any]] ?? []).compactMap { $0["sceneName"] as? String }
        currentScene = responseData["currentProgramSceneName"] as? String ?? currentScene
    }

    private func sendRequest(_ type: String, data: [String: Any] = [:]) {
        send(["op": 6, "d": ["requestType": type, "requestId": UUID().uuidString, "requestData": data]])
    }

    private func send(_ packet: [String: Any]) {
        guard let socket,
              let data = try? JSONSerialization.data(withJSONObject: packet),
              let text = String(data: data, encoding: .utf8) else { return }
        Task { try? await socket.send(.string(text)) }
    }
}
