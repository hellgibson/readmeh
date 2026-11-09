import Foundation
import PDFKit
import SwiftUI

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var documents: [DocumentRecord] = []
    @Published var errorMessage: String?

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var rootURL: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReadMeh", isDirectory: true)
    }
    private var pdfDirectory: URL { rootURL.appendingPathComponent("PDFs", isDirectory: true) }
    private var indexURL: URL { rootURL.appendingPathComponent("library.json") }

    init() {
        do {
            try fileManager.createDirectory(at: pdfDirectory, withIntermediateDirectories: true)
            if let data = try? Data(contentsOf: indexURL) {
                documents = try decoder.decode([DocumentRecord].self, from: data)
            }
        } catch {
            errorMessage = "Your library could not be loaded: \(error.localizedDescription)"
        }
    }

    func importPDF(from sourceURL: URL) {
        let accessGranted = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessGranted { sourceURL.stopAccessingSecurityScopedResource() } }
        do {
            let id = UUID()
            let safeName = sourceURL.lastPathComponent.isEmpty ? "Document.pdf" : sourceURL.lastPathComponent
            let destination = pdfDirectory.appendingPathComponent("\(id.uuidString)-\(safeName)")
            try fileManager.copyItem(at: sourceURL, to: destination)
            guard let pdf = PDFDocument(url: destination) else {
                try? fileManager.removeItem(at: destination)
                throw LibraryError.invalidPDF
            }
            let record = DocumentRecord(id: id, title: sourceURL.deletingPathExtension().lastPathComponent,
                                        filename: destination.lastPathComponent, pageCount: pdf.pageCount)
            documents.insert(record, at: 0)
            try persist()
            errorMessage = nil
        } catch {
            errorMessage = "Could not import this PDF: \(error.localizedDescription)"
        }
    }

    func text(for document: DocumentRecord) throws -> String {
        let url = pdfDirectory.appendingPathComponent(document.filename)
        guard let pdf = PDFDocument(url: url) else { throw LibraryError.invalidPDF }
        let pages = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }
        let result = pages.joined(separator: "\n\n")
            .replacingOccurrences(of: "\u{0000}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw LibraryError.noSelectableText }
        return result
    }

    func updatePosition(for id: UUID, position: Int, force: Bool = false) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        let nextPosition = max(0, position)
        let previousPosition = documents[index].lastPosition
        documents[index].lastPosition = nextPosition
        // Avoid rewriting the library JSON on every spoken word.
        guard force || abs(nextPosition - previousPosition) >= 500 else { return }
        try? persist()
    }

    func delete(_ document: DocumentRecord) {
        try? fileManager.removeItem(at: pdfDirectory.appendingPathComponent(document.filename))
        documents.removeAll { $0.id == document.id }
        try? persist()
    }

    private func persist() throws {
        let data = try encoder.encode(documents)
        try data.write(to: indexURL, options: .atomic)
    }

    enum LibraryError: LocalizedError {
        case invalidPDF, noSelectableText
        var errorDescription: String? {
            switch self {
            case .invalidPDF: return "This file could not be opened as a PDF."
            case .noSelectableText: return "This PDF has no selectable text. Scanned-document OCR is not available yet."
            }
        }
    }
}
