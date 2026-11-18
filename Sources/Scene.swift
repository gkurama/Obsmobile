import SwiftUI

enum SourceKind: String, CaseIterable {
    case camera = "Câmera"
    case screen = "Captura de tela"
    case image = "Imagem"
    case text = "Texto"
    case color = "Cor sólida"
    case teleporter = "Teleporter"
}

struct SourceItem: Identifiable {
    let id = UUID()
    var name: String
    var kind: SourceKind
    var visible = true
    var locked = false
    var x: CGFloat = 0.5
    var y: CGFloat = 0.5
    var scale: CGFloat = 1.0
    var text: String = ""
    var color: Color = .blue
}

struct StudioScene: Identifiable {
    let id = UUID()
    var name: String
    var sources: [SourceItem] = []
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
    ]
    @Published var selectedScene = 0
    @Published var selectedSource: UUID?
    @Published var audio: [AudioChannel] = [
        AudioChannel(name: "Microfone"),
        AudioChannel(name: "Áudio do app")
    ]
    @Published var isStreaming = false
    @Published var isRecording = false
    @Published var teleporterOn = false
    @Published var teleporterAddress = "192.168.0.10"
    @Published var teleporterKey = "teleporter"

    let camera = CameraManager()
    let recorder = Recorder()
    let teleporter = Teleporter()

    var currentScene: StudioScene { scenes[selectedScene] }

    func toggleRecording() {
        if isRecording {
            recorder.stop()
            isRecording = false
        } else {
            recorder.attach(to: camera.session)
            recorder.start()
            isRecording = true
        }
    }

    func toggleTeleporter() {
        if teleporterOn {
            teleporter.stop()
            camera.session.startRunning()
            teleporterOn = false
        } else {
            camera.session.stopRunning()
            teleporter.start(address: "rtmp://\(teleporterAddress)/live",
                             key: teleporterKey)
            teleporterOn = true
        }
    }

    func addScene() {
        scenes.append(StudioScene(name: "Cena \(scenes.count + 1)"))
        selectedScene = scenes.count - 1
    }

    func removeScene() {
        guard scenes.count > 1 else { return }
        scenes.remove(at: selectedScene)
        selectedScene = max(0, selectedScene - 1)
    }

    func addSource(_ kind: SourceKind) {
        var item = SourceItem(name: kind.rawValue, kind: kind)
        if kind == .text { item.text = "Texto" }
        scenes[selectedScene].sources.append(item)
        selectedSource = item.id
    }

    func removeSelectedSource() {
        guard let id = selectedSource else { return }
        scenes[selectedScene].sources.removeAll { $0.id == id }
        selectedSource = nil
    }

    func toggleVisible(_ id: UUID) {
        guard let i = scenes[selectedScene].sources.firstIndex(where: { $0.id == id }) else { return }
        scenes[selectedScene].sources[i].visible.toggle()
    }

    func moveSource(from: IndexSet, to: Int) {
        scenes[selectedScene].sources.move(fromOffsets: from, toOffset: to)
    }
}
