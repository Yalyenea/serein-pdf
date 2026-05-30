import Foundation

enum HighlightExporter {
    static func export(
        _ groups: [DocumentHighlightGroup],
        format: HighlightExportFormat
    ) throws -> Data {
        let sortedGroups = groups.sorted { lhs, rhs in
            if lhs.pageIndex != rhs.pageIndex {
                return lhs.pageIndex < rhs.pageIndex
            }
            return lhs.groupID < rhs.groupID
        }

        switch format {
        case .markdown:
            return Data(renderMarkdown(sortedGroups).utf8)
        case .plainText:
            return Data(renderPlainText(sortedGroups).utf8)
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(sortedGroups.map(makeExportedHighlight))
        }
    }

    static func defaultFilename(for documentTitle: String, format: HighlightExportFormat) -> String {
        let base = documentTitle.isEmpty ? "Highlights" : documentTitle
        return "\(base)-highlights.\(format.fileExtension)"
    }

    private static func renderMarkdown(_ groups: [DocumentHighlightGroup]) -> String {
        guard groups.isEmpty == false else { return "# Highlights\n\n_No highlights._\n" }

        var lines: [String] = ["# Highlights", ""]
        var lastPageIndex: Int?

        for group in groups {
            if lastPageIndex != group.pageIndex {
                if lastPageIndex != nil {
                    lines.append("")
                }
                lines.append("## Page \(group.pageIndex + 1)")
                lines.append("")
                lastPageIndex = group.pageIndex
            }

            lines.append("- \(group.snippet)")
            if group.normalizedComment.isEmpty == false {
                lines.append("  - \(group.comment)")
            }
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func renderPlainText(_ groups: [DocumentHighlightGroup]) -> String {
        guard groups.isEmpty == false else { return "Highlights\n\nNo highlights.\n" }

        var lines: [String] = ["Highlights", ""]
        for (index, group) in groups.enumerated() {
            lines.append("Page \(group.pageIndex + 1) | \(group.color.menuTitle)")
            lines.append("Snippet: \(group.snippet)")
            if group.normalizedComment.isEmpty == false {
                lines.append("Comment: \(group.comment)")
            }
            if index != groups.count - 1 {
                lines.append("")
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func makeExportedHighlight(_ group: DocumentHighlightGroup) -> ExportedHighlight {
        ExportedHighlight(
            page: group.pageIndex + 1,
            snippet: group.snippet,
            color: group.color.rawValue,
            comment: group.normalizedComment.isEmpty ? nil : group.comment,
            createdAt: group.createdAt.map { ISO8601DateFormatter().string(from: $0) }
        )
    }
}
