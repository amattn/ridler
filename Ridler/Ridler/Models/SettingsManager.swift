import Foundation

final class SettingsManager {
    static let shared = SettingsManager()

    private let autoRetryKey = "com.amattn.ridler.autoRetryEnabled"
    private let verboseLogKey = "com.amattn.ridler.verboseLogEnabled"

    var autoRetryEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: autoRetryKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoRetryKey) }
    }

    var verboseLogEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: verboseLogKey) }
        set { UserDefaults.standard.set(newValue, forKey: verboseLogKey) }
    }

    private init() {}
}
