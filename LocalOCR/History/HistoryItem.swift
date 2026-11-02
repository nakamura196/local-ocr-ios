import Foundation

/// One page read and kept in History. Same layout as KotenOCR's, plus which engine read it.
struct HistoryItem: Codable, Identifiable {
    let id: UUID
    let date: Date
    var text: String
    var detections: [Detection]
    let imageFileName: String
    var translatedText: String?
    /// `EngineKind.rawValue`. Optional so records written without it still load.
    var engine: String?
    /// Reading time in seconds.
    var seconds: Double?

    var imagePath: URL {
        HistoryManager.historyDirectory.appendingPathComponent(imageFileName)
    }

    /// Small JPEG used by the history list (generated at save time; may be missing for old items).
    var thumbnailFileName: String { "\(id.uuidString)_thumb.jpg" }

    var engineKind: EngineKind? { engine.flatMap(EngineKind.init(rawValue:)) }
}
