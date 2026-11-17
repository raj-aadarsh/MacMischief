import AppKit

// Developer aid: `MacMischief --snapshot <dir>` renders preview PNGs and exits.
if let flag = CommandLine.arguments.firstIndex(of: "--snapshot") {
    let args = CommandLine.arguments
    let dir = args.count > flag + 1 ? args[flag + 1] : FileManager.default.currentDirectoryPath
    MainActor.assumeIsolated { SnapshotRenderer.run(outDir: dir) }
    exit(0)
}

if let flag = CommandLine.arguments.firstIndex(of: "--snapshot3d"), CommandLine.arguments.count > flag + 1 {
    let dir = CommandLine.arguments[flag + 1]
    MainActor.assumeIsolated { Snapshot3D.run(outDir: dir) }
    exit(0)
}

if let flag = CommandLine.arguments.firstIndex(of: "--spike3d"), CommandLine.arguments.count > flag + 1 {
    let dir = CommandLine.arguments[flag + 1]
    MainActor.assumeIsolated { Spike3D.run(outDir: dir) }
    exit(0)
}

if let flag = CommandLine.arguments.firstIndex(of: "--iconset"), CommandLine.arguments.count > flag + 1 {
    let dir = CommandLine.arguments[flag + 1]
    MainActor.assumeIsolated { SnapshotRenderer.renderIconSet(to: dir) }
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
