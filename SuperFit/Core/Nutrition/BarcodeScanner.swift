import SwiftUI
#if canImport(AVFoundation) && !targetEnvironment(simulator)
import AVFoundation

/// Camera barcode scanner (EAN-13 / EAN-8 / UPC-E). Fires once per scan.
struct BarcodeScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let vc = ScannerController()
        vc.onScan = onScan
        return vc
    }

    func updateUIViewController(_ vc: ScannerController, context: Context) {}

    final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onScan: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var didFire = false

        override func viewDidLoad() {
            super.viewDidLoad()
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.ean13, .ean8, .upce]

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.frame = view.layer.bounds
            preview.videoGravity = .resizeAspectFill
            view.layer.addSublayer(preview)

            DispatchQueue.global(qos: .userInitiated).async { [session] in
                session.startRunning()
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            session.stopRunning()
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput objects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !didFire,
                  let code = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue
            else { return }
            didFire = true
            onScan?(code)
        }
    }
}

#else

/// Simulator / non-camera fallback: manual barcode entry.
struct BarcodeScannerView: View {
    let onScan: (String) -> Void
    @State private var code = ""

    var body: some View {
        VStack(spacing: 12) {
            Text("Camera unavailable — enter barcode")
                .font(.subheadline).foregroundStyle(.secondary)
            TextField("Barcode", text: $code)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
            Button("Look up") { onScan(code) }
                .disabled(code.count < 8)
        }
        .padding()
    }
}

#endif
