import Foundation
import PDFKit

struct DocumentHighlightGroup {
    let groupID: String
    let pageIndex: Int
    let snippet: String
    let color: HighlightColor
    let createdAt: Date?
    let comment: String
    let primarySelection: PDFSelection?
    let records: [HighlightAnnotationRecord]

    var normalizedComment: String {
        comment.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct DocumentHighlightSection {
    let title: String
    let highlights: [DocumentHighlightGroup]
}

struct DocumentHighlightCache {
    private(set) var groups: [DocumentHighlightGroup]
    private var groupIndexByID: [String: Int]
    private var groupIDByAnnotationID: [ObjectIdentifier: String]

    init(groups: [DocumentHighlightGroup] = []) {
        self.groups = groups
        groupIndexByID = [:]
        groupIDByAnnotationID = [:]
        rebuildIndexes()
    }

    func group(containing annotation: PDFAnnotation) -> DocumentHighlightGroup? {
        guard let groupID = groupIDByAnnotationID[ObjectIdentifier(annotation)],
              let groupIndex = groupIndexByID[groupID],
              groups.indices.contains(groupIndex) else { return nil }
        return groups[groupIndex]
    }

    mutating func upsert(_ updatedGroups: [DocumentHighlightGroup]) {
        guard updatedGroups.isEmpty == false else { return }

        for group in updatedGroups {
            if let index = groupIndexByID[group.groupID] {
                groups[index] = group
            } else {
                groupIndexByID[group.groupID] = groups.count
                groups.append(group)
            }
        }
        rebuildIndexes()
    }

    mutating func removeGroups(withIDs groupIDs: Set<String>) {
        guard groupIDs.isEmpty == false else { return }
        groups.removeAll { groupIDs.contains($0.groupID) }
        rebuildIndexes()
    }

    mutating func clear() {
        groups.removeAll(keepingCapacity: false)
        groupIndexByID.removeAll(keepingCapacity: false)
        groupIDByAnnotationID.removeAll(keepingCapacity: false)
    }

    private mutating func rebuildIndexes() {
        groupIndexByID.removeAll(keepingCapacity: true)
        groupIDByAnnotationID.removeAll(keepingCapacity: true)
        for (index, group) in groups.enumerated() {
            groupIndexByID[group.groupID] = index
            for record in group.records {
                groupIDByAnnotationID[ObjectIdentifier(record.annotation)] = group.groupID
            }
        }
    }
}

struct ExportedHighlight: Codable, Equatable {
    let page: Int
    let snippet: String
    let color: String
    let comment: String?
    let createdAt: String?
}

struct AggregateExportedHighlight: Codable, Equatable {
    let document: String
    let page: Int
    let snippet: String
    let color: String
    let comment: String?
    let createdAt: String?
}

enum HighlightExportFormat: String, CaseIterable {
    case markdown
    case plainText = "plain_text"
    case json

    var title: String {
        switch self {
        case .markdown:
            "Markdown"
        case .plainText:
            "Plain Text"
        case .json:
            "JSON"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown:
            "md"
        case .plainText:
            "txt"
        case .json:
            "json"
        }
    }
}
