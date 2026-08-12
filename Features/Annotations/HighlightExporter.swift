import Foundation

enum HighlightExporter {
    typealias DocumentGroups = (documentTitle: String, groups: [DocumentHighlightGroup])

    static func export(
        _ groups: [DocumentHighlightGroup],
        format: HighlightExportFormat
    ) throws -> Data {
        let sortedGroups = sorted(groups)

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

    static func exportAllOpen(
        _ documents: [DocumentGroups],
        format: HighlightExportFormat
    ) throws -> Data {
        let documents = documents
            .filter { $0.groups.isEmpty == false }
            .map { (documentTitle: $0.documentTitle, groups: sorted($0.groups)) }

        switch format {
        case .markdown:
            return Data(renderAggregateMarkdown(documents).utf8)
        case .plainText:
            return Data(renderAggregatePlainText(documents).utf8)
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(
                documents.flatMap { document in
                    document.groups.map { makeAggregateExportedHighlight($0, document: document.documentTitle) }
                }
            )
        }
    }

    static func defaultFilename(for documentTitle: String, format: HighlightExportFormat) -> String {
        let base = documentTitle.isEmpty ? "Highlights" : documentTitle
        return "\(base)-highlights.\(format.fileExtension)"
    }

    static func defaultAllOpenFilename(format: HighlightExportFormat) -> String {
        "All-Open-highlights.\(format.fileExtension)"
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

    private static func renderAggregateMarkdown(_ documents: [DocumentGroups]) -> String {
        guard documents.isEmpty == false else { return "# Highlights\n\n_No highlights._\n" }

        var lines: [String] = ["# Highlights", ""]
        for (documentIndex, document) in documents.enumerated() {
            lines.append("## \(document.documentTitle)")
            lines.append("")
            var lastPageIndex: Int?
            for group in document.groups {
                if lastPageIndex != group.pageIndex {
                    if lastPageIndex != nil {
                        lines.append("")
                    }
                    lines.append("### Page \(group.pageIndex + 1)")
                    lines.append("")
                    lastPageIndex = group.pageIndex
                }
                lines.append("- \(group.snippet)")
                if group.normalizedComment.isEmpty == false {
                    lines.append("  - \(group.comment)")
                }
            }
            if documentIndex != documents.count - 1 {
                lines.append("")
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func renderAggregatePlainText(_ documents: [DocumentGroups]) -> String {
        guard documents.isEmpty == false else { return "Highlights\n\nNo highlights.\n" }

        var lines: [String] = ["Highlights", ""]
        for (documentIndex, document) in documents.enumerated() {
            lines.append("Document: \(document.documentTitle)")
            var lastPageIndex: Int?
            for group in document.groups {
                if lastPageIndex != group.pageIndex {
                    lines.append("Page \(group.pageIndex + 1)")
                    lastPageIndex = group.pageIndex
                }
                lines.append("Snippet: \(group.snippet)")
                lines.append("Color: \(group.color.menuTitle)")
                if group.normalizedComment.isEmpty == false {
                    lines.append("Comment: \(group.comment)")
                }
            }
            if documentIndex != documents.count - 1 {
                lines.append("")
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func sorted(_ groups: [DocumentHighlightGroup]) -> [DocumentHighlightGroup] {
        groups.sorted { lhs, rhs in
            if lhs.pageIndex != rhs.pageIndex {
                return lhs.pageIndex < rhs.pageIndex
            }
            return lhs.groupID < rhs.groupID
        }
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

    private static func makeAggregateExportedHighlight(
        _ group: DocumentHighlightGroup,
        document: String
    ) -> AggregateExportedHighlight {
        AggregateExportedHighlight(
            document: document,
            page: group.pageIndex + 1,
            snippet: group.snippet,
            color: group.color.rawValue,
            comment: group.normalizedComment.isEmpty ? nil : group.comment,
            createdAt: group.createdAt.map { ISO8601DateFormatter().string(from: $0) }
        )
    }
}
