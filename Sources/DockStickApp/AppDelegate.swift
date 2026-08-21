import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let tap = PointerGuardTap()
    private var trustPoll: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()
        buildStatusItem()

        tap.onDisplaysChanged = { [weak self] in self?.rebuildMenu() }
        tap.onFailure = { [weak self] message in self?.report(message) }

        guard ensureAccessibilityAccess() else {
            // Granting access happens over in System Settings, out of our
            // control and with no notification back. Poll instead of making the
            // user relaunch -- there is no API to observe the change.
            rebuildMenu()
            waitForAccessibilityAccess()
            return
        }

        startGuard()
    }

    func applicationWillTerminate(_ notification: Notification) {
        trustPoll?.invalidate()
        tap.stop()
    }

    // MARK: - Permission

    private func ensureAccessibilityAccess() -> Bool {
        // Spelled literally: the SDK exports the key as a mutable global,
        // which Swift 6 refuses to read from a concurrency-checked context.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func waitForAccessibilityAccess() {
        trustPoll?.invalidate()
        trustPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            Task { @MainActor in
                guard let self else { return }
                self.trustPoll = nil
                self.startGuard()
            }
        }
    }

    // MARK: - Guard control

    private func startGuard() {
        if tap.start() {
            rebuildMenu()
        } else {
            report("Không tạo được event tap. Kiểm tra quyền Accessibility rồi mở lại app.")
            rebuildMenu()
        }
    }

    private func report(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Dock Stick Forever"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: - Menu

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "pin.fill",
            accessibilityDescription: "Dock Stick Forever"
        )
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let trusted = AXIsProcessTrusted()
        let active = trusted && tap.isRunning && tap.guardModel != nil

        let status: String
        if !trusted {
            status = "Chưa có quyền Accessibility"
        } else if !tap.isRunning {
            status = "Đã dừng"
        } else if tap.displays.count < 2 {
            status = "Chỉ có một màn hình — không cần giữ"
        } else if !Settings.isEnabled {
            status = "Đang tắt"
        } else {
            status = "Đang giữ Dock ở \(tap.resolvedAnchor().name)"
        }
        let header = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let toggle = NSMenuItem(
            title: "Bật giữ Dock",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggle.target = self
        toggle.state = Settings.isEnabled ? .on : .off
        menu.addItem(toggle)

        // Anchor picker
        let anchorMenu = NSMenu()
        let anchorID = tap.displays.isEmpty ? nil : tap.resolvedAnchor().uuid
        for display in tap.displays {
            let label = display.isMain ? "\(display.name) (chính)" : display.name
            let item = NSMenuItem(title: label, action: #selector(selectAnchor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = display.uuid
            item.state = (display.uuid == anchorID) ? .on : .off
            anchorMenu.addItem(item)
        }
        let anchorItem = NSMenuItem(title: "Neo Dock ở màn hình", action: nil, keyEquivalent: "")
        anchorItem.submenu = anchorMenu
        anchorItem.isEnabled = !tap.displays.isEmpty
        menu.addItem(anchorItem)

        // Guard band width
        let bandMenu = NSMenu()
        for height in [2, 4, 8, 16] as [CGFloat] {
            let item = NSMenuItem(
                title: "\(Int(height)) pt",
                action: #selector(selectBand(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = height
            item.state = (Settings.triggerHeight == height) ? .on : .off
            bandMenu.addItem(item)
        }
        let bandItem = NSMenuItem(title: "Độ dày vùng chặn", action: nil, keyEquivalent: "")
        bandItem.submenu = bandMenu
        menu.addItem(bandItem)

        let warp = NSMenuItem(title: "Chế độ mạnh (warp con trỏ)", action: #selector(toggleWarp), keyEquivalent: "")
        warp.target = self
        warp.state = Settings.warpFallback ? .on : .off
        menu.addItem(warp)

        menu.addItem(.separator())

        let login = NSMenuItem(title: "Mở cùng đăng nhập", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(login)

        if !trusted {
            let grant = NSMenuItem(
                title: "Cấp quyền Accessibility…",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            grant.target = self
            menu.addItem(grant)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Thoát", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.appearsDisabled = !active
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        Settings.isEnabled.toggle()
        tap.rebuildGuard()
        rebuildMenu()
    }

    @objc private func selectAnchor(_ sender: NSMenuItem) {
        guard let uuid = sender.representedObject as? String else { return }
        Settings.anchorUUID = uuid
        tap.rebuildGuard()
        rebuildMenu()
    }

    @objc private func selectBand(_ sender: NSMenuItem) {
        guard let height = sender.representedObject as? CGFloat else { return }
        Settings.triggerHeight = height
        tap.rebuildGuard()
        rebuildMenu()
    }

    @objc private func toggleWarp() {
        Settings.warpFallback.toggle()
        rebuildMenu()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            report("Không đổi được thiết lập mở cùng đăng nhập: \(error.localizedDescription)")
        }
        rebuildMenu()
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )!
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
