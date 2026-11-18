import AVFoundation
import SwiftUI

final class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published private(set) var status = "Aguardando câmera"
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private(set) var position: AVCaptureDevice.Position = .front
    private let sessionQueue = DispatchQueue(label: "com.g.obsmobile.capture")
    private var isConfigured = false

    func start(completion: (() -> Void)? = nil) {
        if isConfigured {
            sessionQueue.async { [weak self] in
                guard let self else { return }
                if !self.session.isRunning { self.session.startRunning() }
                self.setStatus("Câmera pronta")
                if let completion { DispatchQueue.main.async(execute: completion) }
            }
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            requestAudioThenConfigure(completion: completion)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                guard granted else {
                    self.setStatus("Permita o acesso à câmera nos Ajustes do iPhone")
                    if let completion { DispatchQueue.main.async(execute: completion) }
                    return
                }
                self.requestAudioThenConfigure(completion: completion)
            }
        default:
            setStatus("Permita o acesso à câmera nos Ajustes do iPhone")
            if let completion { DispatchQueue.main.async(execute: completion) }
        }
    }

    func pause(completion: (() -> Void)? = nil) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            if let completion { DispatchQueue.main.async(execute: completion) }
        }
    }

    private func requestAudioThenConfigure(completion: (() -> Void)?) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                self?.configureAndStart(completion: completion)
            }
        default:
            configureAndStart(completion: completion)
        }
    }

    private func configureAndStart(completion: (() -> Void)?) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.isConfigured {
                if !self.session.isRunning { self.session.startRunning() }
                self.setStatus("Câmera pronta")
                if let completion { DispatchQueue.main.async(execute: completion) }
                return
            }
            self.session.beginConfiguration()
            self.session.sessionPreset = .high
            let hasCamera = self.setVideo(position: self.position)
            if let mic = AVCaptureDevice.default(for: .audio),
               let input = try? AVCaptureDeviceInput(device: mic),
               self.session.canAddInput(input) {
                self.session.addInput(input)
                self.audioInput = input
            }
            self.session.commitConfiguration()

            guard hasCamera else {
                self.setStatus("Não foi possível configurar a câmera")
                if let completion { DispatchQueue.main.async(execute: completion) }
                return
            }
            self.isConfigured = true
            self.session.startRunning()
            self.setStatus("Câmera pronta")
            if let completion { DispatchQueue.main.async(execute: completion) }
        }
    }

    @discardableResult
    private func setVideo(position: AVCaptureDevice.Position) -> Bool {
        guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: dev),
              session.canAddInput(input) else { return false }
        if let old = videoInput { session.removeInput(old) }
        session.addInput(input)
        videoInput = input
        self.position = position
        return true
    }

    func flip() {
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured else { return }
            self.session.beginConfiguration()
            let target: AVCaptureDevice.Position = self.position == .front ? .back : .front
            let changed = self.setVideo(position: target)
            self.session.commitConfiguration()
            if !changed { self.setStatus("A câmera selecionada não está disponível") }
        }
    }

    private func setStatus(_ value: String) {
        DispatchQueue.main.async { self.status = value }
    }
}
