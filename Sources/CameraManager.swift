import AVFoundation
import SwiftUI

final class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private(set) var position: AVCaptureDevice.Position = .front

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            guard ok else { return }
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.global(qos: .userInitiated).async {
                    self.configure()
                    self.session.startRunning()
                }
            }
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high
        setVideo(position: position)
        if let mic = AVCaptureDevice.default(for: .audio),
           let input = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(input) {
            session.addInput(input)
            audioInput = input
        }
        session.commitConfiguration()
    }

    private func setVideo(position: AVCaptureDevice.Position) {
        if let old = videoInput { session.removeInput(old) }
        guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: dev),
              session.canAddInput(input) else { return }
        session.addInput(input)
        videoInput = input
        self.position = position
    }

    func flip() {
        session.beginConfiguration()
        setVideo(position: position == .front ? .back : .front)
        session.commitConfiguration()
    }
}
