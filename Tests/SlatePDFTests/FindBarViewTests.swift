import AppKit
import XCTest
@testable import SlatePDF

@MainActor
private final class FindBarDelegateSpy: NSObject, FindBarDelegate {
    struct Submission: Equatable {
        let query: String
        let scope: SearchScope
    }

    var submissions: [Submission] = []

    func findBar(_ view: FindBarView, didSubmitQuery query: String, scope: SearchScope) {
        submissions.append(Submission(query: query, scope: scope))
    }

    func findBarRequestsSelectNext(_ view: FindBarView) {}
    func findBarRequestsSelectPrevious(_ view: FindBarView) {}
    func findBarRequestsActivateSelection(_ view: FindBarView) {}
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
}
