import AppKit
import SwiftUI
import Translation

@MainActor
protocol TranslationTaskHosting: AnyObject {
    var view: NSView { get }
    func start(_ request: SelectionTranslation.Request)
    func cancel()
}

/// SwiftUI supplies the system session and its download UI; all visible content stays in AppKit.
@available(macOS 15.0, *)
@MainActor
final class AppleTranslationBridge: TranslationTaskHosting {
    private final class Model: ObservableObject {
        @Published var configuration: TranslationSession.Configuration?
        var request: SelectionTranslation.Request?
        let translation: SelectionTranslation

        init(translation: SelectionTranslation) {
            self.translation = translation
        }
    }

    private struct AppKitContent: NSViewRepresentable {
        let content: NSView
        func makeNSView(context: Context) -> NSView { content }
        func updateNSView(_ nsView: NSView, context: Context) {}
    }

    private struct TranslationContent: View {
        let content: NSView
        @ObservedObject var model: Model

        var body: some View {
            let request = model.request
            let translation = model.translation
            AppKitContent(content: content)
                .translationTask(model.configuration) { @Sendable session in
                    guard let request else { return }
                    do {
                        let response = try await session.translate(request.text)
                        await translation.complete(request, with: .success(response.targetText))
                    } catch {
                        await translation.complete(request, with: .failure(error))
                    }
                }
        }
    }

    private let model: Model
    let view: NSView

    init(content: NSView, translation: SelectionTranslation) {
        model = Model(translation: translation)
        let hostingView = NSHostingView(rootView: TranslationContent(content: content, model: model))
        hostingView.sizingOptions = []
        view = hostingView
    }

    func start(_ request: SelectionTranslation.Request) {
        model.request = request
        if model.configuration?.target == request.targetLanguage {
            model.configuration?.invalidate()
        } else {
            model.configuration = TranslationSession.Configuration(source: nil, target: request.targetLanguage)
        }
    }

    func cancel() {
        model.configuration = nil
        model.request = nil
        view.removeFromSuperview()
    }
}
