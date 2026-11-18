import AVFoundation
import Photos

final class Recorder: NSObject, AVCaptureFileOutputRecordingDelegate {
    private let movieOutput = AVCaptureMovieFileOutput()
    private var session: AVCaptureSession?
    var onFinish: ((URL?) -> Void)?

    var isRecording: Bool { movieOutput.isRecording }

    func attach(to session: AVCaptureSession) {
        self.session = session
        session.beginConfiguration()
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        session.commitConfiguration()
    }

    func start() {
        guard !movieOutput.isRecording else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gravacao-\(Int(Date().timeIntervalSince1970)).mov")
        movieOutput.startRecording(to: url, recordingDelegate: self)
    }

    func stop() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
    }

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        guard error == nil else { onFinish?(nil); return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                self.onFinish?(nil)
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
            }) { _, _ in
                self.onFinish?(outputFileURL)
            }
        }
    }
}
