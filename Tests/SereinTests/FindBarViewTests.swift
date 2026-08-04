import AppKit
import XCTest
@testable import Serein

@MainActor
private final class FindBarDelegateSpy: NSObject, FindBarDelegate {
    struct Submission: Equatable {
        let query: String
        let scope: SearchScope
    }

    var submissions: [Submission] = []
    var selectedNextCount = 0
    var activatedSelectionCount = 0
    var onSelectNext: ((FindBarView) -> Void)?

    func findBar(_ view: FindBarView, didSubmitQuery query: String, scope: SearchScope) {
        submissions.append(Submission(query: query, scope: scope))
    }

    func findBarRequestsSelectNext(_ view: FindBarView) {
        selectedNextCount += 1
        onSelectNext?(view)
    }
    func findBarRequestsSelectPrevious(_ view: FindBarView) {}
    func findBarRequestsActivateSelection(_ view: FindBarView) {
        activatedSelectionCount += 1
    }
    func findBarRequestsNext(_ view: FindBarView) {}
    func findBarRequestsPrevious(_ view: FindBarView) {}
    func findBarRequestsClose(_ view: FindBarView) {}
}

@MainActor
final class FindBarViewTests: XCTestCase {
    func testControlTextDidChangeDoesNotSubmitSearch() {
        let view = FindBarView()
        let delegate = FindBarDelegateSpy()
        view.delegate = delegate
        view.setQuery("needle")

        view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))

        XCTAssertTrue(delegate.submissions.isEmpty)
    }

    func testInsertNewlineSubmitsCurrentQueryAndScope() {
        let view = FindBarView()
        let delegate = FindBarDelegateSpy()
        view.delegate = delegate
        view.setQuery("needle")
        view.setScope(.allOpen)

        let handled = view.control(NSTextField(), textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))

        XCTAssertTrue(handled)
        XCTAssertEqual(delegate.submissions, [FindBarDelegateSpy.Submission(query: "needle", scope: .allOpen)])
    }

    func testScopeChangeWithExistingQuerySubmitsSearch() throws {
        let view = FindBarView()
        let delegate = FindBarDelegateSpy()
        view.delegate = delegate
        view.setQuery("needle")

        let scopeControl = try XCTUnwrap(view.subviews.compactMap { $0 as? NSSegmentedControl }.first)
        scopeControl.selectedSegment = 1

        let target = try XCTUnwrap(scopeControl.target as? NSObject)
        let action = try XCTUnwrap(scopeControl.action)
        _ = target.perform(action, with: scopeControl)

        XCTAssertEqual(delegate.submissions, [FindBarDelegateSpy.Submission(query: "needle", scope: .allOpen)])
    }

    func testArrowSelectionMakesNextEnterActivateCurrentMatch() {
        let view = FindBarView()
        let delegate = FindBarDelegateSpy()
        view.delegate = delegate
        view.setQuery("needle")
        delegate.onSelectNext = { view in
            view.setStatus(matchIndex: 1, totalMatches: 3)
        }

        XCTAssertTrue(
            view.control(NSTextField(), textView: NSTextView(), doCommandBy: #selector(NSResponder.moveDown(_:)))
        )
        XCTAssertTrue(
            view.control(NSTextField(), textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        )

        XCTAssertEqual(delegate.selectedNextCount, 1)
        XCTAssertEqual(delegate.activatedSelectionCount, 1)
        XCTAssertTrue(delegate.submissions.isEmpty)
    }

    func testEnterAfterActivatingKeyboardSelectionSubmitsSameQueryAgain() {
        let view = FindBarView()
        let delegate = FindBarDelegateSpy()
        view.delegate = delegate
        view.setQuery("needle")
        delegate.onSelectNext = { view in
            view.setStatus(matchIndex: 0, totalMatches: 2)
        }

        _ = view.control(NSTextField(), textView: NSTextView(), doCommandBy: #selector(NSResponder.moveDown(_:)))
        _ = view.control(NSTextField(), textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        _ = view.control(NSTextField(), textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(delegate.activatedSelectionCount, 1)
        XCTAssertEqual(delegate.submissions, [FindBarDelegateSpy.Submission(query: "needle", scope: .currentDocument)])
    }
}
