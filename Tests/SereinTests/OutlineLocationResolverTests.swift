import Foundation
import Testing
@testable import Serein

struct OutlineLocationResolverTests {
    @Test
    func samePageHeadingsBecomeCurrentOnlyAfterCrossingViewportTop() {
        let resolver = OutlineLocationResolver(nodes: [
            heading("Introduction", page: 0, y: 700),
            heading("Methods", page: 0, y: 400),
            heading("Results", page: 1, y: 700),
        ])
        #expect(activePath(resolver, page: 0, y: 720) == nil)
        #expect(activePath(resolver, page: 0, y: 700) == [0])
        #expect(activePath(resolver, page: 0, y: 401) == [0])
        #expect(activePath(resolver, page: 0, y: 400) == [1])
        #expect(activePath(resolver, page: 1, y: 720) == [1])
        #expect(activePath(resolver, page: 1, y: 690) == [2])
        #expect(activePath(resolver, page: 0, y: 600) == [0])
    }

    @Test
    func deepestHeadingWinsSharedDestinationButLaterSectionEndsThatChapter() {
        let resolver = OutlineLocationResolver(nodes: [
            heading("Chapter", page: 0, y: 700, children: [
                heading("Section", page: 0, y: 700, children: [
                    heading("Detail", page: 0, y: 500),
                ]),
            ]),
            heading("Next chapter", page: 0, y: 200),
        ])
        #expect(activePath(resolver, page: 0, y: 700) == [0, 0])
        #expect(activePath(resolver, page: 0, y: 450) == [0, 0, 0])
        #expect(activePath(resolver, page: 0, y: 100) == [1])
    }

    @Test
    func focusedComparisonMatchesSourceAndIgnoresOtherDocuments() {
        let sourceID = UUID()
        let comparisonID = UUID()
        let otherID = UUID()
        let resolver = OutlineLocationResolver(nodes: [
            heading("Source", page: 0, y: 700, sourceID: sourceID),
            heading("Other", page: 0, y: 300, sourceID: otherID),
            OutlineNode(title: "No destination", pageIndex: nil, children: []),
        ])
        let position = ReadingPosition(pageIndex: 0, point: CGPoint(x: 0, y: 100))
        #expect(resolver.activeEntryIndex(at: position, sessionIDs: [sourceID, comparisonID]) == 0)
        #expect(resolver.activeEntryIndex(at: position, sessionIDs: [otherID]) == 1)
        #expect(resolver.activeEntryIndex(at: position, sessionIDs: [UUID()]) == nil)
    }

    private func activePath(_ resolver: OutlineLocationResolver, page: Int, y: CGFloat) -> [Int]? {
        resolver.activeEntryIndex(
            at: ReadingPosition(pageIndex: page, point: CGPoint(x: 0, y: y)),
            sessionIDs: []
        ).map { resolver.entries[$0].path }
    }

    private func heading(
        _ title: String,
        page: Int,
        y: CGFloat,
        sourceID: UUID? = nil,
        children: [OutlineNode] = []
    ) -> OutlineNode {
        OutlineNode(
            title: title,
            pageIndex: page,
            destinationPoint: CGPoint(x: 0, y: y),
            children: children,
            sourceSessionID: sourceID
        )
    }
}
