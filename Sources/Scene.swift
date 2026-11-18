import SwiftUI
import AVFoundation
import Photos
import UIKit

enum SourceKind: String, CaseIterable, Codable {
    case camera = "Câmera"
    case image = "Imagem"
    case text = "Texto"
    case color = "Cor sólida"
}

struct SourceItem: Identifiable, Codable {
    let id: UUID
    var name: String
    var kind: SourceKind
    var visible = true
    var locked = false
    var x: CGFloat = 0.5
    var y: CGFloat = 0.5
    var scale: CGFloat = 1.0
    var text: String = ""
    var color: Color = .blue
    var imageData: Data?

    init(id: UUID = UUID(), name: String, kind: SourceKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, visible, locked, x, y, scale, text, imageData, red, green, blue, alpha
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        kind = try values.decode(SourceKind.self, forKey: .kind)
        visible = try values.decodeIfPresent(Bool.self, forKey: .visible) ?? true
        locked = try values.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        x = try values.decodeIfPresent(CGFloat.self, forKey: .x) ?? 0.5
        y = try values.decodeIfPresent(CGFloat.self, forKey: .y) ?? 0.5
        scale = try values.decodeIfPresent(CGFloat.self, forKey: .scale) ?? 1
        text = try values.decodeIfPresent(String.self, forKey: .text) ?? ""
        imageData = try values.decodeIfPresent(Data.self, forKey: .imageData)
        color = Color(
            .sRGB,
            red: try values.decodeIfPresent(Double.self, forKey: .red) ?? 0.1,
            green: try values.decodeIfPresent(Double.self, forKey: .green) ?? 0.35,
            blue: try values.decodeIfPresent(Double.self, forKey: .blue) ?? 0.95,
            opacity: try values.decodeIfPresent(Double.self, forKey: .alpha) ?? 1
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(kind, forKey: .kind)
        try values.encode(visible, forKey: .visible)
        try values.encode(locked, forKey: .locked)
        try values.encode(x, forKey: .x)
        try values.encode(y, forKey: .y)
        try values.encode(scale, forKey: .scale)
        try values.encode(text, forKey: .text)
        try values.encodeIfPresent(imageData, forKey: .imageData)
        var red: CGFloat = 0.1, green: CGFloat = 0.35, blue: CGFloat = 0.95, alpha: CGFloat = 1
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        try values.encode(Double(red), forKey: .red)
        try values.encode(Double(green), forKey: .green)
        try values.encode(Double(blue), forKey: .blue)
        try values.encode(Double(alpha), forKey: .alpha)
    }
}

struct StudioScene: Identifiable, Codable {
    let id: UUID
    var name: String
    var sources: [SourceItem] = []

    init(id: UUID = UUID(), name: String, sources: [SourceItem] = []) {
        self.id = id
        self.name = name
        self.sources = sources
    }
}

struct AudioChannel: Identifiable {
    let id = UUID()
    var name: String
    var volume: Double = 0.8
    var muted = false
}

final class StudioModel: ObservableObject {
    @Published var scenes: [StudioScene] = [
        StudioScene(name: "Cena", sources: [
            SourceItem(name: "Câmera frontal", kind: .camera)
        ])
    ] { didSet { scheduleSceneSave() } }
    @Published var selectedScene = 0 {
        didSet { teleporter.updateScene(currentScene) }
    }
    @Published var selectedSource: UUID?
    @Published var audio: [AudioChannel] = [
        AudioChannel(name: "Microfone"),
        AudioChannel(name: "Áudio do app")
    ]
    @Published var isStreaming = false
    @Published var isStartingStreaming = false
    @Published var isRecording = false
    @Published var teleporterOn = false
    @Published var rtmpURL = "rtmp://192.168.0.10:1935/live"
    @Published var streamKey = "teleporter"
    @Published var screenRecordingCount = 0
    @Published var screenRecordingStatus = ""
    @Published var isScreenCapturing = false
    @Published var isPreparingScreenCapture = false
    let camera = CameraManager()
    let recorder = Recorder()
    let teleporter = Teleporter()
    private var pendingSceneSave: DispatchWorkItem?
    private var screenCaptureMonitor: Timer?

    init() {
        let shared = UserDefaults(suiteName: "group.com.g.obsmobile.shared")
        rtmpURL = shared?.string(forKey: "rtmpURL") ?? rtmpURL
        streamKey = shared?.string(forKey: "streamKey") ?? streamKey
        if let file = sceneLibraryURL(),
           let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([StudioScene].self, from: data),
           !saved.isEmpty {
            scenes = saved
        }
    }

    var currentScene: StudioScene {
        guard scenes.indices.contains(selectedScene) else {
            return scenes[0]
        }
        return scenes[selectedScene]
    }

    func toggleStreaming() {
        guard !rtmpURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !streamKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isRecording, !isStartingStreaming else { return }
        toggleTeleporter()
    }

    func saveBroadcastSettings() {
        let shared = UserDefaults(suiteName: "group.com.g.obsmobile.shared")
        shared?.set(rtmpURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "rtmpURL")
        shared?.set(streamKey.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "streamKey")
    }

    func saveAudioSettings() {
        guard let shared = UserDefaults(suiteName: "group.com.g.obsmobile.shared") else { return }
        for channel in audio {
            let key = channel.name == "Microfone" ? "microphone" : "appAudio"
            shared.set(channel.muted ? 0.0 : channel.volume, forKey: "audioVolume.\(key)")
        }
    }

    func refreshScreenRecordings() {
        guard let folder = screenRecordingsFolder() else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        screenRecordingCount = files.filter { ["mov", "mp4"].contains($0.pathExtension.lowercased()) }.count
    }

    func importScreenRecordings() {
        guard let folder = screenRecordingsFolder() else {
            screenRecordingStatus = "O grupo compartilhado do app não está disponível"
            return
        }
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["mov", "mp4"].contains($0.pathExtension.lowercased()) }
        guard !files.isEmpty else {
            screenRecordingStatus = "Não há gravações de tela para importar"
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] authorization in
            guard authorization == .authorized || authorization == .limited else {
                DispatchQueue.main.async { self?.screenRecordingStatus = "Permita salvar vídeos na Fototeca" }
                return
            }
            for file in files {
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: file)
                }) { saved, error in
                    if saved { try? FileManager.default.removeItem(at: file) }
                    DispatchQueue.main.async {
                        if let error { self?.screenRecordingStatus = "Erro ao salvar: \(error.localizedDescription)" }
                        self?.refreshScreenRecordings()
                        if saved { self?.screenRecordingStatus = "Gravação de tela salva na Fototeca" }
                    }
                }
            }
        }
    }

    private func screenRecordingsFolder() -> URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.g.obsmobile.shared") else { return nil }
        return container.appendingPathComponent("ScreenBroadcasts", isDirectory: true)
    }

    private func scheduleSceneSave() {
        pendingSceneSave?.cancel()
        let snapshot = scenes
        let work = DispatchWorkItem { [weak self] in
            guard let file = Self.sceneLibraryURL(),
                  let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: file, options: .atomic)
            self?.pendingSceneSave = nil
        }
        pendingSceneSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private static func sceneLibraryURL() -> URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return documents.appendingPathComponent("scene-library.json")
    }

    private func sceneLibraryURL() -> URL? { Self.sceneLibraryURL() }

    func toggleRecording() {
        if isRecording {
            recorder.stop()
            isRecording = false
        } else {
            guard !isScreenCapturing, !isPreparingScreenCapture else { return }
            if teleporterOn { stopCameraStreaming() }
            camera.start {
                guard !self.isScreenCapturing, !self.isPreparingScreenCapture else { return }
                self.recorder.attach(to: self.camera.session)
                self.recorder.start()
                self.isRecording = true
            }
        }
    }

    func toggleTeleporter() {
        if teleporterOn {
            stopCameraStreaming()
        } else {
            guard let components = URLComponents(string: rtmpURL),
                  ["rtmp", "rtmps"].contains(components.scheme?.lowercased() ?? ""),
                  components.host != nil, !isStartingStreaming,
                  !isScreenCapturing, !isPreparingScreenCapture else { return }
            if isRecording {
                recorder.stop()
                isRecording = false
            }
            saveBroadcastSettings()
            let captureSession = camera.session
            let selectedPosition = camera.position
            let selectedScene = currentScene
            isStartingStreaming = true
            DispatchQueue.global(qos: .userInitiated).async {
                if captureSession.isRunning { captureSession.stopRunning() }
                DispatchQueue.main.async {
                    self.teleporter.start(address: self.rtmpURL, key: self.streamKey, cameraPosition: selectedPosition, scene: selectedScene)
                    self.isStartingStreaming = false
                    self.teleporterOn = true
                    self.isStreaming = true
                }
            }
        }
    }

    func prepareForScreenCapture(_ launchPicker: @escaping () -> Void) {
        guard !isPreparingScreenCapture, !isStartingStreaming else { return }
        isPreparingScreenCapture = true
        if isRecording {
            recorder.stop()
            isRecording = false
        }
        if teleporterOn { stopCameraStreaming() }
        saveBroadcastSettings()
        let pickerAfterCameraStops = { [weak self] in
            self?.camera.pause {
                launchPicker()
            }
        }
        screenCaptureMonitor?.invalidate()
        let pickerOpenedAt = Date()
        screenCaptureMonitor = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            DispatchQueue.main.async {
                guard let self else { timer.invalidate(); return }
                let active = UserDefaults(suiteName: "group.com.g.obsmobile.shared")?.bool(forKey: "screenCaptureActive") ?? false
                if active {
                    self.isScreenCapturing = true
                    self.isPreparingScreenCapture = false
                } else if self.isPreparingScreenCapture && Date().timeIntervalSince(pickerOpenedAt) > 45 {
                    // The system picker can be cancelled. Restore camera preview after it closes.
                    self.isPreparingScreenCapture = false
                    self.camera.start()
                    timer.invalidate()
                    self.screenCaptureMonitor = nil
                } else if self.isScreenCapturing {
                    self.isScreenCapturing = false
                    self.camera.start()
                    timer.invalidate()
                    self.screenCaptureMonitor = nil
                }
            }
        }
        pickerAfterCameraStops()
    }

    func syncScreenCaptureState() {
        let active = UserDefaults(suiteName: "group.com.g.obsmobile.shared")?.bool(forKey: "screenCaptureActive") ?? false
        isScreenCapturing = active
        if !active {
            isPreparingScreenCapture = false
            camera.start()
        } else {
            camera.pause()
        }
    }

    private func stopCameraStreaming() {
        teleporter.stop()
        teleporterOn = false
        isStreaming = false
        camera.start()
    }

    func addScene() {
        scenes.append(StudioScene(name: "Cena \(scenes.count + 1)"))
        selectedScene = scenes.count - 1
    }

    func removeScene() {
        guard scenes.count > 1 else { return }
        scenes.remove(at: selectedScene)
        selectedScene = min(max(0, selectedScene - 1), scenes.count - 1)
        selectedSource = nil
    }

    func addSource(_ kind: SourceKind) {
        var item = SourceItem(name: kind.rawValue, kind: kind)
        if kind == .text { item.text = "Texto" }
        scenes[selectedScene].sources.append(item)
        selectedSource = item.id
        teleporter.updateScene(currentScene)
    }

    func removeSelectedSource() {
        guard let id = selectedSource else { return }
        scenes[selectedScene].sources.removeAll { $0.id == id }
        selectedSource = nil
        teleporter.updateScene(currentScene)
    }

    func toggleVisible(_ id: UUID) {
        guard let i = scenes[selectedScene].sources.firstIndex(where: { $0.id == id }) else { return }
        scenes[selectedScene].sources[i].visible.toggle()
        teleporter.updateScene(currentScene)
    }

    func moveSource(from: IndexSet, to: Int) {
        scenes[selectedScene].sources.move(fromOffsets: from, toOffset: to)
        teleporter.updateScene(currentScene)
    }

    func moveSource(_ id: UUID, by translation: CGSize, in size: CGSize) {
        guard let index = scenes[selectedScene].sources.firstIndex(where: { $0.id == id }),
              size.width > 0, size.height > 0 else { return }
        scenes[selectedScene].sources[index].x = min(max(0, scenes[selectedScene].sources[index].x + translation.width / size.width), 1)
        scenes[selectedScene].sources[index].y = min(max(0, scenes[selectedScene].sources[index].y + translation.height / size.height), 1)
        teleporter.updateScene(currentScene)
    }

    func updateSourceText(_ id: UUID, text: String) {
        guard let index = scenes[selectedScene].sources.firstIndex(where: { $0.id == id }) else { return }
        scenes[selectedScene].sources[index].text = text
        teleporter.updateScene(currentScene)
    }

    func updateSourceImage(_ id: UUID, data: Data) {
        guard let index = scenes[selectedScene].sources.firstIndex(where: { $0.id == id }) else { return }
        scenes[selectedScene].sources[index].imageData = data
        teleporter.updateScene(currentScene)
    }

    func updateSourceColor(_ id: UUID, color: Color) {
        guard let index = scenes[selectedScene].sources.firstIndex(where: { $0.id == id }) else { return }
        scenes[selectedScene].sources[index].color = color
        teleporter.updateScene(currentScene)
    }

    func updateSourceScale(_ id: UUID, scale: CGFloat) {
        guard let index = scenes[selectedScene].sources.firstIndex(where: { $0.id == id }) else { return }
        scenes[selectedScene].sources[index].scale = scale
        teleporter.updateScene(currentScene)
    }
}
