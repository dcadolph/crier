import Foundation
import Observation

import CrierKit

// SettingsStore persists Settings in user defaults as JSON and tells listeners when they change.
@MainActor
@Observable
final class SettingsStore {
    // settings is the live configuration. Every change is saved and announced immediately.
    var settings: Settings {
        didSet {
            guard settings != oldValue else {
                return
            }
            save()
            for listener in listeners {
                listener(oldValue)
            }
        }
    }

    // theme is the theme look drawn over the settings, or nil to draw them as chosen. It is remembered under its
    // own key and never saved into settings, so clearing it puts back exactly what the reader had. A change runs
    // the listeners with the settings as they are, so the ticker redraws in the new colors.
    var theme: ThemeLook? {
        didSet {
            guard theme != oldValue else {
                return
            }
            UserDefaults.standard.set(theme?.message ?? "", forKey: Self.themeKey)
            for listener in listeners {
                listener(settings)
            }
        }
    }

    // drawn is what the ticker and the band draw: the settings with the theme look over them, when one is held.
    var drawn: Settings {
        settings.drawn(with: theme)
    }

    // listeners run after every change with the settings as they were before it.
    @ObservationIgnored private var listeners: [@MainActor (Settings) -> Void] = []

    // key is the user defaults key holding the encoded settings.
    private static let key = "settings"
    // themeKey is the user defaults key holding the theme look's message.
    private static let themeKey = "themeLook"

    // init loads saved settings, or the defaults when none are saved or they fail to decode.
    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
            let saved = try? JSONDecoder().decode(Settings.self, from: data)
        {
            settings = saved
        } else {
            settings = Settings()
        }
        theme = ThemeLookMessage(UserDefaults.standard.string(forKey: Self.themeKey) ?? "").updating(nil)
    }

    // onChange adds a listener that runs after every change with the previous settings.
    func onChange(_ listener: @escaping @MainActor (Settings) -> Void) {
        listeners.append(listener)
    }

    // reset restores the defaults but keeps the emergency choices, so a reset never turns emergency mode on or
    // moves where Crier watches for warnings.
    func reset() {
        var defaults = Settings()
        defaults.emergency = settings.emergency
        settings = defaults
    }

    // save writes the settings to user defaults.
    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
