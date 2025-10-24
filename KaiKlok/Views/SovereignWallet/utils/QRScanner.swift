//
//  QRScanner.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/15/25.
//

import SwiftUI
import AVFoundation

struct QRScannerView<T: Decodable>: UIViewControllerRepresentable {
    typealias UIViewControllerType = ScannerViewController

    final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onScanned: (T?) -> Void

        private let captureSession = AVCaptureSession()
        private var previewLayer: AVCaptureVideoPreviewLayer?

        init(onScanned: @escaping (T?) -> Void) {
            self.onScanned = onScanned
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()

            guard let videoCaptureDevice = AVCaptureDevice.default(for: .video),
                  let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice),
                  captureSession.canAddInput(videoInput)
            else {
                onScanned(nil)
                return
            }

            captureSession.addInput(videoInput)

            let metadataOutput = AVCaptureMetadataOutput()
            guard captureSession.canAddOutput(metadataOutput) else {
                onScanned(nil)
                return
            }

            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]

            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer?.videoGravity = .resizeAspectFill
            previewLayer?.frame = view.layer.bounds
            if let layer = previewLayer {
                view.layer.addSublayer(layer)
            }

            captureSession.startRunning()
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            captureSession.stopRunning()

            if let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
               let stringValue = metadataObject.stringValue,
               let data = stringValue.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(T.self, from: data) {
                onScanned(decoded)
            } else {
                onScanned(nil)
            }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.bounds
        }
    }

    let onScanned: (T?) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        return ScannerViewController(onScanned: onScanned)
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}
