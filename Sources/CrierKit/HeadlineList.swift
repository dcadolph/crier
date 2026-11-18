import SwiftUI

// HeadlineList lists the ticker's entries with their outlet, how many outlets carry them, and their age.
// Clicking a row opens the headline.
public struct HeadlineList: View {
    // entries are the headlines to list.
    let entries: [Entry]
    // onOpen runs when a row is clicked. When nil, the headline's link opens in the browser.
    let onOpen: ((Entry) -> Void)?

    // openURL opens links when there is no onOpen.
    @Environment(\.openURL) private var openURL

    // init builds a list.
    public init(entries: [Entry], onOpen: ((Entry) -> Void)? = nil) {
        self.entries = entries
        self.onOpen = onOpen
    }

    // body draws one row per entry.
    public var body: some View {
        List(entries) { entry in
            Button {
                if let onOpen {
                    onOpen(entry)
                } else {
                    openURL(entry.headline.lead.link)
                }
            } label: {
                row(entry)
            }
            .buttonStyle(.plain)
        }
    }

    // row draws one entry: its marks and title over a line of detail.
    private func row(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                if entry.major {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                }
                if let tag = entry.tag {
                    Text(tag.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.22)))
                }
                Text(entry.headline.lead.title)
                    .lineLimit(2)
            }
            Text(detail(entry))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    // detail describes the entry's outlet, its outlet count, and when it first appeared.
    private func detail(_ entry: Entry) -> String {
        var parts = [entry.headline.lead.outlet]
        let count = entry.headline.outlets.count
        if count > 1 {
            parts.append("\(count) outlets")
        }
        if let first = entry.headline.first {
            parts.append(first.formatted(.relative(presentation: .named)))
        }
        return parts.joined(separator: " · ")
    }
}
