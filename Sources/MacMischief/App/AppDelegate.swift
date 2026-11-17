import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let manager = OverlayManager()
    private let mischiefs = MischiefRegistry.all
    private var model: MenuModel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let restored = Settings.activeMischief.flatMap { id in mischiefs.first { $0.id == id } }

        model = MenuModel(
            items: mischiefs.map {
                MischiefCardInfo(id: $0.id, title: $0.title, emoji: $0.emoji, tagline: $0.tagline,
                                 colors: $0.colors.map { Color(hex: $0) })
            },
            activeID: restored?.id,
            hideInFullScreen: manager.hideInFullScreen
        )
        model.onSelect = { [weak self] id in self?.select(id) }
        model.onHideInFullScreen = { [weak self] on in
            Settings.hideInFullScreen = on
            self?.manager.hideInFullScreen = on
        }
        model.onQuit = { NSApp.terminate(nil) }

        let host = NSHostingController(rootView: MenuView(model: model))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        statusItem = item

        select(restored?.id)
    }

    private func select(_ id: String?) {
        let mischief = id.flatMap { id in mischiefs.first { $0.id == id } }
        manager.activateOnly(mischief)
        Settings.activeMischief = mischief?.id
        model.activeID = mischief?.id
        updateIcon(mischief)
    }

    private func updateIcon(_ mischief: (any Mischief)?) {
        let image = NSImage(systemSymbolName: mischief?.symbolName ?? "pawprint.fill",
                            accessibilityDescription: "MacMischief")
        image?.isTemplate = true
        statusItem?.button?.image = image
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
