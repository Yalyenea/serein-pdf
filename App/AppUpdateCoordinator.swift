import AppKit

/// Owns update UI: menu check, launch-time check, download progress, install + relaunch.
@MainActor
final class AppUpdateCoordinator {
    private var isBusy = false
    private var progressAlert: NSAlert?
    private var progressIndicator: NSProgressIndicator?
    private var pendingInstall: (() throws -> Void)?

    private let tokenProvider: () -> String?
    private let autoCheckEnabledProvider: () -> Bool

    init(
        tokenProvider: @escaping () -> String?,
        autoCheckEnabledProvider: @escaping () -> Bool
    ) {
        self.tokenProvider = tokenProvider
        self.autoCheckEnabledProvider = autoCheckEnabledProvider
    }

    func scheduleLaunchCheck(delay: TimeInterval = 2.5) {
        guard autoCheckEnabledProvider() else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await checkForUpdates(userInitiated: false)
        }
    }

    @objc
    func checkForUpdatesFromMenu(_ sender: Any?) {
        Task { @MainActor in
            await checkForUpdates(userInitiated: true)
        }
    }

    func checkForUpdates(userInitiated: Bool) async {
        guard isBusy == false else { return }
        isBusy = true
        defer { isBusy = false }

        let service = makeService()
        do {
            let result = try await service.checkForUpdate()
            switch result {
            case let .upToDate(current, latest):
                if userInitiated {
                    presentInfo(
                        title: "You’re up to date",
                        message: "Serein \(current) is the latest release (GitHub: \(latest))."
                    )
                }
            case let .updateAvailable(release):
                let shouldInstall = presentUpdatePrompt(release: release, userInitiated: userInitiated)
                guard shouldInstall else { return }
                try await downloadAndInstall(release: release, service: service)
            }
        } catch {
            if userInitiated {
                presentError(error)
            } else {
                NSLog("Serein update check failed: %@", error.localizedDescription)
            }
        }
    }

    // MARK: - Private

    private func makeService() -> AppUpdateService {
        let configToken = tokenProvider()
        return AppUpdateService(
            currentVersion: AppUpdateService.bundleShortVersion(),
            githubToken: configToken
        )
    }

    private func downloadAndInstall(release: AppUpdateService.ReleaseInfo, service: AppUpdateService) async throws {
        showProgress(title: "Downloading Serein \(release.version)…")
        defer { hideProgress() }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SereinUpdateDownload-\(UUID().uuidString)", isDirectory: true)
        var installScheduled = false
        defer {
            if installScheduled == false {
                try? FileManager.default.removeItem(at: workDir)
            }
        }
        let dmgURL = try await service.downloadRelease(release, to: workDir) { [weak self] fraction in
            Task { @MainActor in
                self?.updateProgress(fraction)
            }
        }

        updateProgressTitle("Installing Serein \(release.version)…")
        hideProgress()

        presentInfo(
            title: "Update ready",
            message: "Serein will quit and relaunch as \(release.version)."
        )
        pendingInstall = {
            _ = try service.scheduleInstallAndRelaunch(
                dmgURL: dmgURL,
                destinationAppURL: Bundle.main.bundleURL
            )
            installScheduled = true
        }
        defer { pendingInstall = nil }
        NSApp.terminate(nil)
    }

    /// Called only after the application has accepted termination and saved its documents.
    func installPendingUpdate() throws {
        try pendingInstall?()
        pendingInstall = nil
    }

    private func presentUpdatePrompt(release: AppUpdateService.ReleaseInfo, userInitiated: Bool) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Serein \(release.version) is available"
        alert.informativeText = userInitiated
            ? "Download and install this update from GitHub Releases now? Serein will relaunch when finished."
            : "A new version is available on GitHub. Download and install now? Serein will relaunch when finished."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Later")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentInfo(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Update failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showProgress(title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "Please wait…"
        alert.alertStyle = .informational

        let indicator = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 240, height: 16))
        indicator.isIndeterminate = true
        indicator.style = .bar
        indicator.startAnimation(nil)
        alert.accessoryView = indicator

        progressAlert = alert
        progressIndicator = indicator

        // Non-blocking presentation via window.
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window) { _ in }
        } else {
            alert.window.makeKeyAndOrderFront(nil)
        }
    }

    private func updateProgress(_ fraction: Double) {
        guard let indicator = progressIndicator else { return }
        if indicator.isIndeterminate {
            indicator.isIndeterminate = false
            indicator.minValue = 0
            indicator.maxValue = 1
        }
        indicator.doubleValue = fraction
    }

    private func updateProgressTitle(_ title: String) {
        progressAlert?.messageText = title
    }

    private func hideProgress() {
        if let alert = progressAlert, let window = alert.window.sheetParent {
            window.endSheet(alert.window)
        }
        progressAlert?.window.orderOut(nil)
        progressAlert = nil
        progressIndicator = nil
    }
}

#if DEBUG
extension AppUpdateCoordinator {
    func testingSetPendingInstall(_ action: @escaping () throws -> Void) {
        pendingInstall = action
    }
}
#endif
