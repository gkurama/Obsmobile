import SwiftUI
import PhotosUI
import UIKit

struct ContentView: View {
    @EnvironmentObject var studio: StudioModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var obsRemote = OBSRemoteControl()

    var body: some View {
        VStack(spacing: 6) {
            PreviewArea()
                .frame(maxHeight: .infinity)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 6) {
                    ScenesPanel().frame(width: 170)
                    SourcesPanel().frame(width: 210)
                    MixerPanel().frame(width: 190)
                    ControlsPanel().frame(width: 220)
                    OBSRemotePanel(remote: obsRemote).frame(width: 230)
                    PCMonitorPanel().frame(width: 240)
                    TeleprompterPanel(remote: obsRemote).frame(width: 250)
                }
            }
            .frame(height: 210)
        }
        .padding(6)
        .background(Color(white: 0.11))
        .onAppear {
            studio.syncScreenCaptureState()
            if !studio.isScreenCapturing { studio.camera.start() }
            studio.refreshScreenRecordings()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                studio.syncScreenCaptureState()
                studio.refreshScreenRecordings()
            }
        }
    }
}

struct OBSRemotePanel: View {
    @ObservedObject var remote: OBSRemoteControl
    @State private var address = "ws://192.168.0.10:4455"
    @State private var password = ""

    var body: some View {
        Panel(title: "OBS no PC") {
            TextField("ws://IP:4455", text: $address)
                .textFieldStyle(.roundedBorder)
                .font(.caption2)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Senha WebSocket", text: $password)
                .textFieldStyle(.roundedBorder)
                .font(.caption2)
            HStack {
                Button(remote.isConnected ? "Desligar" : "Conectar") {
                    if remote.isConnected { remote.disconnect() }
                    else { remote.connect(address: address, password: password) }
                }
                Button("Live") { remote.startStreaming() }.disabled(!remote.isConnected)
                Button("Parar") { remote.stopStreaming() }.disabled(!remote.isConnected)
            }
            Text(remote.status).font(.caption2).foregroundColor(.secondary)
            Text("Cena: \(remote.currentScene.isEmpty ? "—" : remote.currentScene)")
                .font(.caption2).foregroundColor(.white)
            ScrollView {
                ForEach(remote.scenes, id: \.self) { scene in
                    Button(scene) { remote.selectScene(scene) }
                        .font(.caption2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct TeleprompterPanel: View {
    @ObservedObject var remote: OBSRemoteControl
    @AppStorage("teleprompter.script") private var script = ""
    @AppStorage("teleprompter.obsInput") private var obsInput = "Teleprompter"
    @State private var showingPrompt = false

    var body: some View {
        Panel(title: "Teleprompter") {
            TextField("Nome da fonte de texto no OBS", text: $obsInput)
                .textFieldStyle(.roundedBorder)
                .font(.caption2)
                .textInputAutocapitalization(.never)
            TextEditor(text: $script)
                .font(.caption)
                .frame(minHeight: 65, maxHeight: 85)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.4)))
            HStack {
                Button("Enviar texto ao OBS") {
                    remote.updateTextInput(named: obsInput, text: script)
                }.disabled(!remote.isConnected || script.isEmpty)
                Button("Ler") { showingPrompt = true }.disabled(script.isEmpty)
            }
            Text(remote.isConnected ? "Texto enviado pela conexão OBS" : "Conecte o OBS WebSocket para sincronizar")
                .font(.caption2).foregroundColor(.secondary)
            Text("No OBS, adicione um filtro Deslizar à fonte para rolar o texto.")
                .font(.caption2).foregroundColor(.secondary)
        }
        .fullScreenCover(isPresented: $showingPrompt) {
            TeleprompterRunner(text: script)
        }
    }
}

struct TeleprompterRunner: View {
    let text: String
    @Environment(\.dismiss) private var dismiss
    @State private var isRunning = false
    @State private var startedAt = Date()
    @State private var elapsedBeforePause = 0.0
    @State private var speed = 32.0
    @State private var mirrored = false

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button("Fechar") { dismiss() }
                Spacer()
                Button(isRunning ? "Pausar" : "Iniciar") {
                    if isRunning {
                        elapsedBeforePause += Date().timeIntervalSince(startedAt)
                        isRunning = false
                    } else {
                        startedAt = Date()
                        isRunning = true
                    }
                }
                Button(mirrored ? "Normal" : "Espelhar") { mirrored.toggle() }
            }
            HStack {
                Text("Velocidade")
                Slider(value: $speed, in: 10...100)
            }
            GeometryReader { geometry in
                TimelineView(.animation(minimumInterval: 0.04, paused: !isRunning)) { timeline in
                    Text(text)
                        .font(.system(size: 34, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .lineSpacing(14)
                        .frame(width: geometry.size.width - 40, alignment: .leading)
                        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                        .offset(y: -(elapsedBeforePause + (isRunning ? timeline.date.timeIntervalSince(startedAt) : 0)) * speed + 30)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .clipped()
                }
            }
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding()
        .background(Color(white: 0.08).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

struct PCMonitorPanel: View {
    @StateObject private var monitor = RTMPMonitor()
    @State private var address = "rtmp://192.168.0.10:1935/preview"
    @State private var key = "obs"

    var body: some View {
        Panel(title: "PC → iPhone") {
            RTMPVideoMonitor(monitor: monitor)
                .frame(height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            TextField("URL RTMP de entrada", text: $address)
                .textFieldStyle(.roundedBorder)
                .font(.caption2)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Chave do sinal", text: $key)
                .textFieldStyle(.roundedBorder)
                .font(.caption2)
            HStack {
                Button("Assistir") { monitor.play(address: address, key: key) }
                Button("Parar") { monitor.stop() }
            }
            Text(monitor.status).font(.caption2).foregroundColor(.secondary)
        }
    }
}

struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 0.2))
            content().padding(.horizontal, 4)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.16))
        .cornerRadius(4)
    }
}

struct PreviewArea: View {
    @EnvironmentObject var studio: StudioModel

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                ForEach(studio.currentScene.sources) { src in
                    if src.visible {
                        sourceView(src)
                            .scaleEffect(src.scale)
                            .position(x: geo.size.width * src.x,
                                      y: geo.size.height * src.y)
                            .contentShape(Rectangle())
                            .onTapGesture { studio.selectedSource = src.id }
                            .gesture(DragGesture().onEnded { value in
                                studio.moveSource(src.id, by: value.translation, in: geo.size)
                            })
                            .overlay(
                                Rectangle()
                                    .stroke(Color.red, lineWidth: studio.selectedSource == src.id ? 2 : 0)
                            )
                    }
                }
                if studio.camera.status != "Câmera pronta" {
                    Text(studio.camera.status)
                        .font(.caption)
                        .padding(8)
                        .background(.black.opacity(0.7))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .clipped()
        }
    }

    @ViewBuilder
    func sourceView(_ src: SourceItem) -> some View {
        switch src.kind {
        case .camera:
            CameraPreview(session: studio.camera.session)
        case .color:
            Rectangle().fill(src.color).frame(width: 200, height: 120)
        case .text:
            Text(src.text).font(.largeTitle.bold()).foregroundColor(.white)
        case .image:
            if let data = src.imageData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 320, maxHeight: 240)
            } else {
                Image(systemName: "photo").resizable().scaledToFit().frame(width: 120).foregroundColor(.gray)
            }
        }
    }
}

struct ScenesPanel: View {
    @EnvironmentObject var studio: StudioModel

    var body: some View {
        Panel(title: "Cenas") {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(studio.scenes.enumerated()), id: \.element.id) { i, sc in
                        Text(sc.name)
                            .font(.caption).foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(4)
                            .background(studio.selectedScene == i ? Color.blue : Color.clear)
                            .onTapGesture { studio.selectedScene = i }
                    }
                }
            }
            HStack {
                Button("+") { studio.addScene() }
                Button("−") { studio.removeScene() }
            }
            .buttonStyle(.bordered)
        }
    }
}

struct SourcesPanel: View {
    @EnvironmentObject var studio: StudioModel
    @State private var pickedImage: PhotosPickerItem?

    var body: some View {
        Panel(title: "Fontes") {
            List {
                ForEach(studio.currentScene.sources) { src in
                    HStack {
                        Image(systemName: src.visible ? "eye" : "eye.slash")
                            .onTapGesture { studio.toggleVisible(src.id) }
                        Text(src.name).font(.caption)
                    }
                    .listRowBackground(studio.selectedSource == src.id ? Color.blue : Color.clear)
                    .onTapGesture { studio.selectedSource = src.id }
                }
                .onMove(perform: studio.moveSource)
            }
            .listStyle(.plain)
            .frame(minHeight: 55, maxHeight: 90)
            if let selected = studio.currentScene.sources.first(where: { $0.id == studio.selectedSource }), selected.kind == .text {
                TextField("Texto da fonte", text: Binding(
                    get: { studio.currentScene.sources.first(where: { $0.id == selected.id })?.text ?? "" },
                    set: { studio.updateSourceText(selected.id, text: $0) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.caption2)
            }
            if let selected = studio.currentScene.sources.first(where: { $0.id == studio.selectedSource }), selected.kind == .image {
                PhotosPicker("Escolher imagem", selection: $pickedImage, matching: .images)
                    .font(.caption2)
                    .onChange(of: pickedImage) { item in
                        guard let item else { return }
                        Task {
                            if let data = try? await item.loadTransferable(type: Data.self) {
                                studio.updateSourceImage(selected.id, data: data)
                            }
                        }
                    }
            }
            if let selected = studio.currentScene.sources.first(where: { $0.id == studio.selectedSource }), selected.kind == .color {
                ColorPicker("Cor", selection: Binding(
                    get: { studio.currentScene.sources.first(where: { $0.id == selected.id })?.color ?? .blue },
                    set: { studio.updateSourceColor(selected.id, color: $0) }
                ))
                .font(.caption2)
            }
            if let selected = studio.currentScene.sources.first(where: { $0.id == studio.selectedSource }) {
                HStack {
                    Text("Tamanho").font(.caption2)
                    Slider(value: Binding(
                        get: { studio.currentScene.sources.first(where: { $0.id == selected.id })?.scale ?? 1 },
                        set: { studio.updateSourceScale(selected.id, scale: $0) }
                    ), in: 0.25...2)
                }
            }
            HStack {
                Menu("+") {
                    ForEach(SourceKind.allCases, id: \.self) { kind in
                        Button(kind.rawValue) { studio.addSource(kind) }
                    }
                }
                Button("−") { studio.removeSelectedSource() }
            }
            .buttonStyle(.bordered)
        }
    }
}

struct MixerPanel: View {
    @EnvironmentObject var studio: StudioModel

    var body: some View {
        Panel(title: "Mixer de áudio") {
            ForEach($studio.audio) { $ch in
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(ch.name).font(.caption2).foregroundColor(.white)
                        Spacer()
                        Image(systemName: ch.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .foregroundColor(ch.muted ? .red : .white)
                            .onTapGesture { ch.muted.toggle() }
                    }
                    Slider(value: $ch.volume)
                }
            }
        }
    }
}

struct ControlsPanel: View {
    @EnvironmentObject var studio: StudioModel
    @State private var startLegacyBroadcast = false

    var body: some View {
        Panel(title: "Controles") {
            ScrollView(.vertical, showsIndicators: false) {
              VStack(spacing: 4) {
                Button(studio.isStreaming ? "Parar câmera RTMP" : (studio.isStartingStreaming ? "Preparando câmera…" : "Transmitir câmera RTMP")) {
                    studio.toggleStreaming()
                }
                .disabled(studio.isStartingStreaming || studio.isScreenCapturing || studio.isPreparingScreenCapture || studio.camera.status != "Câmera pronta" || studio.rtmpURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || studio.streamKey.isEmpty)
                Button(studio.isRecording ? "Parar gravação" : "Iniciar gravação") {
                    studio.toggleRecording()
                }
                .disabled(studio.isScreenCapturing || studio.isPreparingScreenCapture || studio.isStartingStreaming)
                TextField("URL RTMP do servidor", text: $studio.rtmpURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption2)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: studio.rtmpURL) { _ in studio.saveBroadcastSettings() }
                SecureField("Stream key", text: $studio.streamKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption2)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: studio.streamKey) { _ in studio.saveBroadcastSettings() }
                Button("YouTube: preencher servidor") {
                    studio.rtmpURL = "rtmp://a.rtmp.youtube.com/live2"
                }
                if #available(iOS 27.0, *) {
                    ModernScreenCaptureControl(prepareForCapture: studio.prepareForScreenCapture)
                        .disabled(studio.isPreparingScreenCapture || studio.isStartingStreaming)
                } else {
                    Button("Transmitir ecrã do iPhone") {
                        studio.prepareForScreenCapture { startLegacyBroadcast = true }
                    }
                    .disabled(studio.isPreparingScreenCapture || studio.isScreenCapturing || studio.isStartingStreaming)
                    ScreenBroadcastPicker(startRequested: $startLegacyBroadcast)
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                }
                if studio.isScreenCapturing || studio.isPreparingScreenCapture {
                    Text(studio.isScreenCapturing
                         ? screenCaptureStopHint
                         : "A preparar modo ecrã…")
                        .font(.caption2).foregroundColor(.orange)
                }
                Button("Salvar gravações de ecrã (\(studio.screenRecordingCount))") {
                    studio.importScreenRecordings()
                }
                Text(studio.screenRecordingStatus).font(.caption2).foregroundColor(.secondary)
                ForEach($studio.audio) { $channel in
                    HStack(spacing: 4) {
                        Text(channel.name).font(.caption2)
                        Slider(value: $channel.volume, in: 0...1)
                            .onChange(of: channel.volume) { _ in studio.saveAudioSettings() }
                        Button(channel.muted ? "Mudo" : "Som") { channel.muted.toggle(); studio.saveAudioSettings() }
                            .font(.caption2)
                    }
                }
                Text(studio.isScreenCapturing ? "Câmera pausada durante captura do ecrã" : studio.teleporter.status)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Button("Virar câmera") { studio.camera.flip() }
              }
              .font(.caption)
              .buttonStyle(.bordered)
              .frame(maxWidth: .infinity)
            }
        }
    }

    private var screenCaptureStopHint: String {
        if #available(iOS 27.0, *) { return "Modo ecrã ativo · toque para parar" }
        return "Modo ecrã ativo · pare pelo indicador do iOS"
    }
}
