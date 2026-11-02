import CoreGraphics

/// Places line-number tags at the start of their lines, just outside the box: above a
/// vertical line, left of a horizontal one. A tag is first sized to its line's width, so tags of
/// neighbouring lines stay apart however crowded the page is; on a dense page they are small
/// until the reader zooms in (tags zoom with the image). A tag much smaller than the page's
/// typical one (a thin side note) is then grown where it covers no other box or tag. When there
/// is no room before the image edge the tag goes inside the start of its box.
enum LineTagLayout {
    /// Clear space between a tag and its box. Not shrunk with small tags: the tag's rim and the
    /// box line would otherwise close it (two-digit tags, shrunk most, looked stuck to the box).
    static let gap: CGFloat = 3
    /// Regular tag height; the font is three quarters of the tag height.
    static let regularHeight: CGFloat = 12
    /// A tag on a thin line (傍書 and the like) is never smaller than this, so its number stays legible.
    /// Lines of a uniformly dense page are not "thin" (they are all alike) and keep the small tags that
    /// keep neighbours apart; the reader zooms in there.
    static let minimumLegibleHeight: CGFloat = 9
    /// A line is thin when it is under this share of the page's typical line thickness.
    static let thinShare: CGFloat = 0.6

    static func regularSize(for number: Int) -> CGSize {
        CGSize(width: CGFloat(8 + 5 * String(number).count), height: regularHeight)
    }

    /// Box outline width for a page: 8% of its typical line thickness (the median of the
    /// boxes' short sides), between 0.5 and 1.5 pt. A fixed 1.5 pt took a quarter of a
    /// 12 pt column.
    static func boxLineWidth(for rects: [CGRect]) -> CGFloat {
        let thickness = rects.map { min($0.width, $0.height) }.sorted()
        guard !thickness.isEmpty else { return 1.5 }
        return min(1.5, max(0.5, thickness[thickness.count / 2] * 0.08))
    }

    static func frames(for rects: [CGRect], in bounds: CGRect? = nil) -> [CGRect] {
        let area = bounds ?? CGRect(x: 0, y: 0, width: CGFloat.greatestFiniteMagnitude,
                                    height: CGFloat.greatestFiniteMagnitude)
        var tags = rects.enumerated().map { index, rect in
            let regular = regularSize(for: index + 1)
            let vertical = rect.height >= rect.width
            let scale = min(1, vertical ? rect.width / regular.width : rect.height / regular.height)
            return place(CGSize(width: regular.width * scale, height: regular.height * scale), at: rect, in: area)
        }
        // A thin line among regular ones (a side note, 傍書) would get a tag far smaller than its
        // neighbours'. Grow it toward the page's typical tag height, as far as it stays clear of
        // the other boxes and tags.
        let heights = tags.map(\.height).sorted()
        guard !heights.isEmpty else { return tags }
        let typical = heights[heights.count / 2]
        for (index, rect) in rects.enumerated() where tags[index].height < typical - 0.001 {
            let regular = regularSize(for: index + 1)
            let natural = tags[index].height
            for step in 0..<4 {
                let height = typical - (typical - natural) * CGFloat(step) / 4
                let size = CGSize(width: regular.width * height / regular.height, height: height)
                let tag = place(size, at: rect, in: area)
                // Half the box gap of clear space, so a grown tag never squeezes up against a neighbour.
                let room = tag.insetBy(dx: -gap / 2, dy: -gap / 2)
                let blocked = rects.indices.contains { other in
                    other != index && (rects[other].intersects(room) || tags[other].intersects(room))
                }
                // Only outside the box: a larger tag inside it would hide more of the first characters.
                if !blocked && !tag.intersects(rect) {
                    tags[index] = tag
                    break
                }
            }
        }
        // Last resort for thin lines (傍書): a floor on the tag size, even where it touches neighbours.
        // Their rim and slight transparency keep overlapping tags readable.
        let thickness = rects.map { min($0.width, $0.height) }.sorted()
        let typicalThickness = thickness[thickness.count / 2]
        for (index, rect) in rects.enumerated() where tags[index].height < minimumLegibleHeight - 0.001 {
            guard min(rect.width, rect.height) < typicalThickness * thinShare else { continue }
            let regular = regularSize(for: index + 1)
            let height = minimumLegibleHeight
            let size = CGSize(width: regular.width * height / regular.height, height: height)
            let base = place(size, at: rect, in: area)
            // Step the tag further out along the line's direction (up for a vertical line, left for a
            // horizontal one) while it would cover another box or tag; keep the first spot if none is clear.
            let vertical = rect.height >= rect.width
            var chosen = base
            for step in 0..<3 {
                let shift = CGFloat(step) * (height + 2)
                let candidate = vertical ? base.offsetBy(dx: 0, dy: -shift) : base.offsetBy(dx: -shift, dy: 0)
                guard area.contains(candidate) else { break }
                let blocked = rects.indices.contains { other in
                    other != index && (rects[other].intersects(candidate) || tags[other].intersects(candidate))
                }
                if !blocked { chosen = candidate; break }
            }
            tags[index] = chosen
        }
        return tags
    }

    /// Outside the start of the line, or inside it when there is no room before the image edge.
    private static func place(_ size: CGSize, at rect: CGRect, in area: CGRect) -> CGRect {
        let vertical = rect.height >= rect.width
        let outside = vertical
            ? CGRect(x: rect.midX - size.width / 2, y: rect.minY - gap - size.height,
                     width: size.width, height: size.height)
            : CGRect(x: rect.minX - gap - size.width, y: rect.midY - size.height / 2,
                     width: size.width, height: size.height)
        if area.contains(outside) { return outside }
        return vertical
            ? CGRect(x: rect.midX - size.width / 2, y: rect.minY + gap, width: size.width, height: size.height)
            : CGRect(x: rect.minX + gap, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }
}
