import Foundation
import UIKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import Combine

/// Upload state for progress tracking.
enum UploadState: Equatable {
    case idle
    case uploading(progress: Double)
    case success(filename: String)
    case error(String)

    var isUploading: Bool {
        if case .uploading = self { return true }
        return false
    }
}

/// Manages file uploads to POST /api/upload.
/// Supports both photo library (PHPicker) and document picker (UIDocumentPicker).
final class FileUploadManager: NSObject, ObservableObject {

    // MARK: - Published state

    @Published var uploadState: UploadState = .idle

    // MARK: - Private

    private let config: ServerConfig
    private var uploadTask: URLSessionDataTask?

    // MARK: - Init

    init(config: ServerConfig) {
        self.config = config
    }

    // MARK: - Public API

    /// Upload a file from a given URL.
    func uploadFile(url: URL, filename: String? = nil) {
        let name = filename ?? url.lastPathComponent
        DebugLogStore.shared.log("Upload file: \(name)", category: .upload)

        // Start accessing security-scoped resource for document picker files
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let fileData = try? Data(contentsOf: url) else {
            DebugLogStore.shared.log("Cannot read file: \(name)", category: .error)
            DispatchQueue.main.async {
                self.uploadState = .error("Cannot read file: \(name)")
            }
            return
        }

        uploadData(fileData, filename: name, mimeType: mimeType(for: url))
    }

    /// Upload image data (from photo picker).
    func uploadImage(_ image: UIImage, filename: String = "photo.jpg") {
        DebugLogStore.shared.log("Upload image: \(filename)", category: .upload)
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            DebugLogStore.shared.log("Cannot encode image", category: .error)
            DispatchQueue.main.async {
                self.uploadState = .error("Cannot encode image")
            }
            return
        }
        uploadData(data, filename: filename, mimeType: "image/jpeg")
    }

    /// Upload raw data with filename.
    func uploadData(_ data: Data, filename: String, mimeType: String) {
        guard let url = URL(string: "\(config.baseURL)/api/upload") else {
            DispatchQueue.main.async {
                self.uploadState = .error("Invalid server URL")
            }
            return
        }

        DispatchQueue.main.async {
            self.uploadState = .uploading(progress: 0)
        }

        // Build multipart/form-data request
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let session = URLSession.shared
        let task = session.dataTask(with: request) { [weak self] responseData, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    DebugLogStore.shared.log("Upload error: \(error.localizedDescription)", category: .error)
                    self?.uploadState = .error(error.localizedDescription)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    DebugLogStore.shared.log("Upload: invalid response", category: .error)
                    self?.uploadState = .error("Invalid response")
                    return
                }

                if httpResponse.statusCode == 200 {
                    DebugLogStore.shared.log("Upload success: \(filename)", category: .upload)
                    self?.uploadState = .success(filename: filename)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if case .success = self?.uploadState {
                            self?.uploadState = .idle
                        }
                    }
                } else {
                    let message = responseData.flatMap { String(data: $0, encoding: .utf8) } ?? "HTTP \(httpResponse.statusCode)"
                    DebugLogStore.shared.log("Upload failed: \(message)", category: .error)
                    self?.uploadState = .error("Upload failed: \(message)")
                }
            }
        }

        // Observe upload progress
        let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async {
                if case .uploading = self?.uploadState {
                    self?.uploadState = .uploading(progress: progress.fractionCompleted)
                }
            }
        }
        // Store observation to keep it alive (auto-released when task completes)
        objc_setAssociatedObject(task, "progressObservation", observation, .OBJC_ASSOCIATION_RETAIN)

        self.uploadTask = task
        task.resume()
    }

    /// Cancel in-progress upload.
    func cancelUpload() {
        uploadTask?.cancel()
        uploadTask = nil
        DispatchQueue.main.async {
            self.uploadState = .idle
        }
    }

    // MARK: - MIME type helper

    private func mimeType(for url: URL) -> String {
        if let utType = UTType(filenameExtension: url.pathExtension) {
            return utType.preferredMIMEType ?? "application/octet-stream"
        }
        return "application/octet-stream"
    }
}

// MARK: - Photo Picker (PHPicker) SwiftUI wrapper

/// A SwiftUI wrapper for PHPickerViewController.
struct PhotoPicker: UIViewControllerRepresentable {
    var onImagePicked: (UIImage, String) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked, dismiss: dismiss)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onImagePicked: (UIImage, String) -> Void
        let dismiss: DismissAction

        init(onImagePicked: @escaping (UIImage, String) -> Void, dismiss: DismissAction) {
            self.onImagePicked = onImagePicked
            self.dismiss = dismiss
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            dismiss()
            guard let result = results.first else { return }

            let filename = result.assetIdentifier ?? "photo_\(Int(Date().timeIntervalSince1970)).jpg"

            result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                guard let image = object as? UIImage else { return }
                DispatchQueue.main.async {
                    self?.onImagePicked(image, filename + ".jpg")
                }
            }
        }
    }
}

// MARK: - Document Picker SwiftUI wrapper

/// A SwiftUI wrapper for UIDocumentPickerViewController.
struct DocumentPicker: UIViewControllerRepresentable {
    var onFilePicked: (URL, String) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFilePicked: onFilePicked, dismiss: dismiss)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFilePicked: (URL, String) -> Void
        let dismiss: DismissAction

        init(onFilePicked: @escaping (URL, String) -> Void, dismiss: DismissAction) {
            self.onFilePicked = onFilePicked
            self.dismiss = dismiss
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onFilePicked(url, url.lastPathComponent)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // No action needed
        }
    }
}
