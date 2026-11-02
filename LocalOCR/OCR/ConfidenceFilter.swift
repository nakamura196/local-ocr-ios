import Foundation

extension Detection {
    /// A line the reader has touched (moved, resized, split, merged, added, or its text edited) is
    /// certain by definition: it gets the top score so the confidence slider never hides it.
    mutating func markReaderConfirmed() { score = 1.0 }
}

/// The result screen's confidence slider. A display filter only: nothing is re-read and the stored
/// lines are never changed by moving the slider.
///
/// Scale note (Local OCR): the four engines score differently. The NDL detectors give a sigmoid-style
/// 0-1 box score (floors 0.3 / 0.25), Vision gives its own confidence (often 0.3, 0.5 or 1.0) and PP-OCR
/// the mean recognition probability. None is calibrated against another, so the slider starts at 0 and
/// hides nothing; the reader raises it to drop the least certain lines of the page in front of them.
enum ConfidenceFilter {
    /// Initial slider value: everything shows.
    static let defaultThreshold: Float = 0
    static let range: ClosedRange<Float> = 0...0.95

    /// Lines at or above `threshold`, each with its index in the full list. A score of exactly the
    /// threshold stays visible.
    static func visible(_ detections: [Detection], threshold: Float) -> [(index: Int, detection: Detection)] {
        detections.enumerated().compactMap { $0.element.score >= threshold ? ($0.offset, $0.element) : nil }
    }

    /// The text of the visible lines, one per line; empty lines are skipped.
    static func text(_ detections: [Detection], threshold: Float) -> String {
        visible(detections, threshold: threshold).map(\.detection.text).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func percentText(_ value: Float) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
