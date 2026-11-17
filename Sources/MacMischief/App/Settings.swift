import Foundation

enum Settings {
    private static var defaults: UserDefaults { .standard }

    /// The one mischief that is running (nil = all quiet).
    static var activeMischief: String? {
        get { defaults.string(forKey: "activeMischief") }
        set { defaults.set(newValue, forKey: "activeMischief") }
    }

    static var hideInFullScreen: Bool {
        get { defaults.object(forKey: "hideInFullScreen") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "hideInFullScreen") }
    }
}
