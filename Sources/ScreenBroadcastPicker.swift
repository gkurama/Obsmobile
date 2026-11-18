import ReplayKit
import SwiftUI

struct ScreenBroadcastPicker: UIViewRepresentable {
    @Binding var startRequested: Bool

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: .zero)
        picker.preferredExtension = "com.g.obsmobile.app.broadcast"
        picker.showsMicrophoneButton = true
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        guard startRequested else { return }
        DispatchQueue.main.async {
            let button = uiView.subviews.compactMap { $0 as? UIButton }.first
            button?.sendActions(for: .touchUpInside)
            startRequested = false
        }
    }
}
