import AppKit
import UserNotifications

import CrierKit

// Notifier posts a notification for each major story the alert rules let through, and opens the story when
// the notification is clicked.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    // store holds the live settings.
    private let store: SettingsStore
    // sent records the alerts already posted, so an event never alerts twice.
    private var sent: [Sent]
    // center posts the notifications.
    private let center = UNUserNotificationCenter.current()

    // key is the user defaults key holding the sent records.
    private static let key = "sent"
    // linkKey is the notification payload key holding the story's link.
    nonisolated private static let linkKey = "link"

    // init loads the sent records and asks for permission when alerts are on.
    init(store: SettingsStore) {
        self.store = store
        if let data = UserDefaults.standard.data(forKey: Self.key),
            let saved = try? JSONDecoder().decode([Sent].self, from: data)
        {
            sent = saved
        } else {
            sent = []
        }
        super.init()
        center.delegate = self
        if store.settings.alerts.enabled {
            authorize()
        }
        store.onChange { [weak self] old in
            if let self, self.store.settings.alerts.enabled, !old.alerts.enabled {
                self.authorize()
            }
        }
    }

    // authorize asks for permission to post alerts.
    private func authorize() {
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                NSLog("crier: notification permission failed: %@", error.localizedDescription)
            }
        }
    }

    // handle posts the headlines that are due. The first refresh after launch posts nothing, since those stories were already out before Crier started.
    func handle(_ headlines: [Headline], first: Bool) {
        guard !first else {
            return
        }
        let now = Date()
        let due = Alerts.due(headlines, rules: store.settings.alerts, sent: sent, now: now)
        for headline in due {
            post(headline)
            sent.append(Sent(keywords: headline.keywords, at: now))
        }
        sent = Alerts.prune(sent, now: now)
        if !due.isEmpty, let data = try? JSONEncoder().encode(sent) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    // post sends one notification for a headline.
    private func post(_ headline: Headline) {
        let content = UNMutableNotificationContent()
        content.title = headline.lead.title
        content.body = "\(headline.lead.outlet) and \(headline.outlets.count - 1) more outlets are reporting this."
        content.sound = .default
        content.userInfo = [Self.linkKey: headline.lead.link.absoluteString]
        let request = UNNotificationRequest(identifier: headline.id, content: content, trigger: nil)
        center.add(request) { error in
            if let error {
                NSLog("crier: notification failed: %@", error.localizedDescription)
            }
        }
    }

    // userNotificationCenter shows alerts even while Crier is the active app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // userNotificationCenter opens the story when its notification is clicked.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let text = info[Self.linkKey] as? String, let url = URL(string: text) else {
            return
        }
        await MainActor.run {
            _ = NSWorkspace.shared.open(url)
        }
    }
}
