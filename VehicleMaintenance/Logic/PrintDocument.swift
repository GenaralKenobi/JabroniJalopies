import UIKit

/// A simple printable page layout: a title, optional section headings, and entries
/// (a bold line with indented bullet points under it). An entry is never split across
/// pages, and entries have generous space between them.
struct PrintDocument {
    struct Entry: Equatable {
        var title: String
        /// Extra text after the title in normal weight, e.g. "×4" or "PSI: ______".
        var suffix: String? = nil
        var bullets: [String] = []
    }

    struct Section: Equatable {
        var heading: String?
        var entries: [Entry]
    }

    var title: String
    var subtitle: String?
    var sections: [Section]
    /// 1 for checklists; 2 for truck lists (entries flow down the left column, then the right).
    var columns: Int = 1
    /// Space after each entry, and extra space after each section (e.g. after everything in the cab).
    var entrySpacing: CGFloat = 36
    /// Space after entries that have bullet points (truck lists use a third less; checklists the same).
    var bulletedEntrySpacing: CGFloat? = nil
    var sectionSpacing: CGFloat = 0
    /// Checklists and truck lists use a larger, underlined title.
    var largeUnderlinedTitle = false

    // US Letter with three-quarter-inch margins.
    static let pageSize = CGSize(width: 612, height: 792)
    static let margin: CGFloat = 54
    static let columnGap: CGFloat = 28

    private static let titleFont = UIFont.systemFont(ofSize: 22, weight: .bold)
    private static let subtitleFont = UIFont.systemFont(ofSize: 12)
    private static let headingFont = UIFont.systemFont(ofSize: 13, weight: .semibold)
    private static let entryFont = UIFont.systemFont(ofSize: 14, weight: .bold)
    private static let suffixFont = UIFont.systemFont(ofSize: 14)
    private static let bulletFont = UIFont.systemFont(ofSize: 12)
    private static let footerFont = UIFont.systemFont(ofSize: 9)
    private static let bulletIndent: CGFloat = 18
    private static let bulletTextIndent: CGFloat = 32

    /// The width of one column.
    var columnWidth: CGFloat {
        let full = Self.pageSize.width - Self.margin * 2
        let count = CGFloat(max(1, columns))
        return (full - Self.columnGap * (count - 1)) / count
    }

    func pdfData() -> Data {
        let page = CGRect(origin: .zero, size: Self.pageSize)
        let margin = Self.margin
        let fullWidth = page.width - margin * 2
        let width = columnWidth
        let bottom = page.height - margin
        let columnCount = max(1, columns)
        var pageNumber = 0
        var column = 0
        var top = margin
        var y = margin

        return UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            var x: CGFloat { margin + CGFloat(column) * (width + Self.columnGap) }
            func newPage() {
                context.beginPage()
                pageNumber += 1
                column = 0
                top = margin
                y = margin
                let footer = Self.text("\(title) · Page \(pageNumber)", Self.footerFont, color: .gray)
                footer.draw(at: CGPoint(x: margin, y: page.height - margin / 2 - 6))
            }
            /// The next column, or a new page after the last one.
            func nextColumn() {
                if column + 1 < columnCount {
                    column += 1
                    y = top
                } else {
                    newPage()
                }
            }
            func draw(_ string: NSAttributedString, x: CGFloat, width: CGFloat) {
                let h = Self.height(string, width)
                string.draw(with: CGRect(x: x, y: y, width: width, height: h),
                            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                y += h
            }

            newPage()
            if largeUnderlinedTitle {
                draw(NSAttributedString(string: title, attributes: [
                    .font: UIFont.systemFont(ofSize: 30, weight: .bold), .foregroundColor: UIColor.black,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ]), x: margin, width: fullWidth)
            } else {
                draw(Self.text(title, Self.titleFont), x: margin, width: fullWidth)
            }
            if let subtitle, !subtitle.isEmpty {
                y += 4
                draw(Self.text(subtitle, Self.subtitleFont, color: .darkGray), x: margin, width: fullWidth)
            }
            y += 24
            top = y

            for section in sections {
                for (index, entry) in section.entries.enumerated() {
                    var needed = Self.entryHeight(entry, width: width)
                    var heading = index == 0 ? section.heading.map { Self.text($0.uppercased(), Self.headingFont, color: .darkGray) } : nil
                    if let heading { needed += Self.height(heading, width) + 8 }
                    // Move on rather than split an entry (unless it's taller than a whole column).
                    // A section that carries on in the next column or page repeats its heading with "(cont.)".
                    if y + needed > bottom && y > top {
                        nextColumn()
                        if heading == nil, let name = section.heading {
                            heading = Self.text("\(name.uppercased()) (CONT.)", Self.headingFont, color: .darkGray)
                        }
                    }
                    if let heading {
                        draw(heading, x: x, width: width)
                        y += 8
                    }
                    draw(Self.entryLine(entry), x: x, width: width)
                    for bullet in entry.bullets {
                        y += 3
                        Self.text("•", Self.bulletFont).draw(at: CGPoint(x: x + Self.bulletIndent, y: y))
                        draw(Self.text(bullet, Self.bulletFont), x: x + Self.bulletTextIndent, width: width - Self.bulletTextIndent)
                    }
                    y += entry.bullets.isEmpty ? entrySpacing : (bulletedEntrySpacing ?? entrySpacing)
                }
                y += sectionSpacing
            }
        }
    }

    /// The height an entry takes, so it can be kept on one page.
    static func entryHeight(_ entry: Entry, width: CGFloat) -> CGFloat {
        var total = height(entryLine(entry), width)
        for bullet in entry.bullets {
            total += 3 + height(text(bullet, bulletFont), width - bulletTextIndent)
        }
        return total
    }

    private static func entryLine(_ entry: Entry) -> NSAttributedString {
        let line = NSMutableAttributedString(attributedString: text(entry.title, entryFont))
        if let suffix = entry.suffix, !suffix.isEmpty {
            line.append(text("   \(suffix)", suffixFont))
        }
        return line
    }

    private static func text(_ string: String, _ font: UIFont, color: UIColor = .black) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
    }

    private static func height(_ string: NSAttributedString, _ width: CGFloat) -> CGFloat {
        ceil(string.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                 options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
    }
}

extension PrintDocument {
    /// A checklist: each item in bold, with what to check as bullet points.
    static func checklist(_ checklist: ChecklistTemplate) -> PrintDocument {
        let items = checklist.items.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
        let entries = items.enumerated().map { index, item in
            Entry(title: "\(index + 1). \(item.title.trimmingCharacters(in: .whitespaces))",
                  suffix: item.requiresReading ? "\(item.readingLabel.isEmpty ? "Reading" : item.readingLabel): ________" : nil,
                  bullets: item.detailLines)
        }
        return PrintDocument(title: checklist.name.isEmpty ? "Checklist" : checklist.name,
                             subtitle: nil, sections: [Section(heading: nil, entries: entries)],
                             columns: 1, entrySpacing: 36, largeUnderlinedTitle: true)
    }

    /// What's on a truck, grouped by where it's kept; kits list what's inside them.
    static func contents(_ items: [TruckItem], truckName: String) -> PrintDocument {
        let sections = TruckContents.grouped(items).map { group in
            Section(heading: group.title, entries: group.items.map { item in
                var bullets = (item.parts ?? []).filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }.map { part in
                    part.quantity.map { "\(part.name) ×\($0)" } ?? part.name
                }
                let notes = item.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                if !notes.isEmpty { bullets.append("Note: \(notes)") }
                return Entry(title: item.name, suffix: item.quantity.map { "×\($0)" }, bullets: bullets)
            })
        }
        return PrintDocument(title: "\(truckName): What's on the Truck", subtitle: nil, sections: sections,
                             columns: 2, entrySpacing: 18, bulletedEntrySpacing: 12, sectionSpacing: 44,
                             largeUnderlinedTitle: true)
    }
}
