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
                        title: L10n.text("You’re up to date", "已是最新版本"),
                        message: L10n.text("Serein \(current) is the latest release (GitHub: \(latest)).", "Serein \(current) 已是最新版本（GitHub：\(latest)）。")
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
        showProgress(title: L10n.text("Downloading Serein \(release.version)…", "正在下载 Serein \(release.version)…"))
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

        updateProgressTitle(L10n.text("Installing Serein \(release.version)…", "正在安装 Serein \(release.version)…"))
        hideProgress()

        presentInfo(
            title: L10n.text("Update ready", "更新已就绪"),
            message: L10n.text("Serein will quit and relaunch as \(release.version).", "Serein 将退出并以 \(release.version) 重新启动。")
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
        alert.messageText = L10n.text("Serein \(release.version) is available", "Serein \(release.version) 已发布")
        alert.informativeText = userInitiated
            ? L10n.text("Download and install this update from GitHub Releases now? Serein will relaunch when finished.", "现在从 GitHub Releases 下载并安装更新？完成后 Serein 将重新启动。")
            : L10n.text("A new version is available on GitHub. Download and install now? Serein will relaunch when finished.", "GitHub 上有新版本。现在下载并安装？完成后 Serein 将重新启动。")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.text("Install", "安装"))
        alert.addButton(withTitle: L10n.text("Later", "稍后"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentInfo(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.text("OK", "好"))
        alert.runModal()
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L10n.text("Update failed", "更新失败")
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text("OK", "好"))
        alert.runModal()
    }

    private func showProgress(title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = L10n.text("Please wait…", "请稍候…")
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
