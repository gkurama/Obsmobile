import SwiftUI

struct ContentView: View {
    @EnvironmentObject var studio: StudioModel

    var body: some View {
        VStack(spacing: 6) {
            PreviewArea()
                .frame(maxHeight: .infinity)
            HStack(alignment: .top, spacing: 6) {
                ScenesPanel()
                SourcesPanel()
                MixerPanel()
                ControlsPanel()
            }
            .frame(height: 170)
        }
        .padding(6)
        .background(Color(white: 0.11))
        .onAppear { studio.camera.start() }
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
                            .overlay(
                                Rectangle()
                                    .stroke(Color.red, lineWidth: studio.selectedSource == src.id ? 2 : 0)
                            )
                    }
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
            Image(systemName: "photo").resizable().scaledToFit().frame(width: 120).foregroundColor(.gray)
        case .screen:
            Text("Captura de tela").foregroundColor(.gray)
        case .teleporter:
            Text("Teleporter").foregroundColor(.green)
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

    var body: some View {
        Panel(title: "Controles") {
            VStack(spacing: 4) {
                Button(studio.isStreaming ? "Parar transmissão" : "Iniciar transmissão") {
                    studio.isStreaming.toggle()
                }
                Button(studio.isRecording ? "Parar gravação" : "Iniciar gravação") {
                    studio.toggleRecording()
                }
                Button(studio.teleporterOn ? "Teleporter: ligado" : "Teleporter: desligado") {
                    studio.toggleTeleporter()
                }
                TextField("IP do PC", text: $studio.teleporterAddress)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption2)
                    .keyboardType(.numbersAndPunctuation)
                Button("Virar câmera") { studio.camera.flip() }
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
        }
    }
}
