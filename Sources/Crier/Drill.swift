#if CRIER_DRILL
    import Foundation
    import os

    import CrierKit

    // Drill runs a recorded tornado warning chain through the emergency feed on a fast clock, so the red ticker,
    // flashing, sound, acknowledging, and clearing can be seen on demand. The warning arrives at once, its update
    // after updateAt, and its cancel after cancelAt. Only builds made with the CRIER_DRILL flag have it.
    final class Drill: Sendable {
        // State is the running drill's start, or nil, and how many drills have run, which keeps each drill's alert
        // ids new so every drill sounds.
        private struct State {
            // start is when the running drill began, or nil when none runs.
            var start: Date?
            // runs counts the drills started since launch.
            var runs = 0
        }

        // state holds the drill's clock, shared with the feed's reads off the main actor.
        private let state = OSAllocatedUnfairLock(initialState: State())

        // updateAt is how many seconds after the start the update arrives.
        static let updateAt: TimeInterval = 30
        // cancelAt is how many seconds after the start the cancel arrives.
        static let cancelAt: TimeInterval = 90
        // length is how long a drill runs before the feed reads the Weather Service again.
        static let length: TimeInterval = 120
        // warningLength is how long the drill's warning would last without its cancel.
        static let warningLength: TimeInterval = 900

        // fetch serves the drill's alerts while a drill runs and reads the Weather Service otherwise.
        var fetch: Fetch {
            { [self] url in
                if let data = data(now: Date()) {
                    return data
                }
                return try await EmergencyFeed.download(url)
            }
        }

        // begin starts a drill now.
        func begin() {
            state.withLock { state in
                state.start = Date()
                state.runs += 1
            }
        }

        // data returns the drill's alerts as the Weather Service would send them at the moment, or nil when no drill
        // runs.
        func data(now: Date) -> Data? {
            let current = state.withLock { state -> (Date, Int)? in
                guard let start = state.start else {
                    return nil
                }
                guard now.timeIntervalSince(start) < Self.length else {
                    state.start = nil
                    return nil
                }
                return (start, state.runs)
            }
            guard let (start, run) = current else {
                return nil
            }
            let elapsed = now.timeIntervalSince(start)
            let warning = "drill-\(run)-warning"
            let update = "drill-\(run)-update"
            var features = [
                Self.feature(id: warning, type: "Alert", sent: start, start: start, references: [])
            ]
            if elapsed >= Self.updateAt {
                features.append(
                    Self.feature(
                        id: update, type: "Update", sent: start.addingTimeInterval(Self.updateAt), start: start,
                        references: [warning]))
            }
            if elapsed >= Self.cancelAt {
                features.append(
                    Self.feature(
                        id: "drill-\(run)-cancel", type: "Cancel", sent: start.addingTimeInterval(Self.cancelAt),
                        start: start, references: [warning, update]))
            }
            return try? JSONSerialization.data(withJSONObject: ["features": features])
        }

        // feature builds one alert in the Weather Service's shape, modeled on the recorded Santa Cruz tornado
        // warning of November 16, 2026.
        private static func feature(id: String, type: String, sent: Date, start: Date, references: [String])
            -> [String: Any]
        {
            let format = ISO8601DateFormatter()
            let ends = format.string(from: start.addingTimeInterval(warningLength))
            return [
                "properties": [
                    "id": id, "event": "Tornado Warning", "messageType": type, "status": "Actual",
                    "severity": "Extreme", "urgency": "Immediate", "areaDesc": "Crier Drill",
                    "headline": "Tornado Warning. This is a Crier drill.", "sent": format.string(from: sent),
                    "expires": ends, "ends": ends,
                    "references": references.map { ["identifier": $0] },
                    "parameters": ["WEAHandling": ["Imminent Threat"]],
                    "instruction": "This is a drill. No action is needed.",
                ] as [String: Any]
            ]
        }
    }
#endif
