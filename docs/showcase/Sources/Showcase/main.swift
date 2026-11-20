import AppKit
import CrierKit
import SwiftUI

// Showcase draws CrierKit's news band inside two made-up apps, one dark and one light, each handing the band its
// own colors. Every outlet, headline, and app here is invented. It renders in an offscreen window, since the
// ticker and the rotation line are AppKit views that ImageRenderer cannot draw, and writes a PNG at twice the
// point size.
//
// Run from the repository root: swift run --package-path docs/showcase Showcase docs/crierkit.png

// Pick is one made-up event: its title, the outlets carrying it, and how many hours ago it broke.
struct Pick {
    // title is the headline.
    let title: String
    // outlets are the made-up publishers carrying it.
    let outlets: [String]
    // hours is how long ago the first outlet ran it.
    let hours: Double
    // tag names the followed topic it belongs to, or nil for general news.
    var tag: String? = nil
}

// picks are the made-up news, biggest first.
let picks = [
    Pick(
        title: "City council approves late-night ferry service across the harbor",
        outlets: ["Harbor Wire", "Northwind Daily", "Meridian Post", "Valley Courier", "The Lantern"], hours: 0.6),
    Pick(
        title: "Public library opens a tool lending branch downtown",
        outlets: ["Northwind Daily", "Alder Gazette", "The Lantern", "Harbor Wire"], hours: 1.4),
    Pick(
        title: "Volunteers count a record 412 monarch butterflies at the reserve",
        outlets: ["Valley Courier", "Meridian Post", "Alder Gazette"], hours: 2.2),
    Pick(
        title: "Regional rail adds weekend trains to the coast this spring",
        outlets: ["Meridian Post", "Harbor Wire", "Northwind Daily"], hours: 3.1),
    Pick(
        title: "Astronomers catalog a new comet visible to the naked eye next month",
        outlets: ["The Lantern", "Valley Courier"], hours: 4.0),
    Pick(
        title: "Farmers market extends its hours through the winter", outlets: ["Alder Gazette", "Harbor Wire"],
        hours: 5.5),
    Pick(title: "Town replaces its 1920s footbridge with a timber span", outlets: ["Northwind Daily"], hours: 6.0),
    Pick(
        title: "Bakery celebrates the 100th birthday of its sourdough starter", outlets: ["Valley Courier"], hours: 7.2),
    Pick(title: "Orchestra plays a free concert in the old rail yard", outlets: ["Meridian Post"], hours: 8.0),
    Pick(title: "High school robotics team builds a trail-clearing rover", outlets: ["Alder Gazette"], hours: 8.5),
    Pick(title: "Lighthouse keeper's logbooks go on display at the museum", outlets: ["Harbor Wire"], hours: 9.0),
    Pick(title: "Cycling path along the river reopens after repairs", outlets: ["The Lantern"], hours: 9.4),
    Pick(title: "Community garden doubles its plots for the spring season", outlets: ["Valley Courier"], hours: 10.0),
    Pick(title: "Night sky park earns a dark-sky designation", outlets: ["Northwind Daily"], hours: 10.5),
    Pick(title: "Ferry crew rescues a sea kayaker near the breakwater", outlets: ["Meridian Post"], hours: 11.0),
    Pick(
        title: "Comet's tail should be visible after dusk by mid-March", outlets: ["The Lantern"], hours: 3.5,
        tag: "Comets"),
    Pick(
        title: "Second comet sighting reported from the hills", outlets: ["Valley Courier"], hours: 6.5,
        tag: "Comets"),
]

// entries groups the picks into ticker entries the way News does, with each outlet's copy five minutes apart.
func entries(now: Date) -> [Entry] {
    var count = 0
    return picks.flatMap { pick in
        let stories = pick.outlets.enumerated().map { index, outlet in
            count += 1
            let slug = outlet.lowercased().filter(\.isLetter)
            return Story(
                title: pick.title, link: URL(string: "https://example.com/\(slug)/\(count)")!, outlet: outlet,
                published: now.addingTimeInterval(-pick.hours * 3600 - Double(index) * 300), sourceID: slug)
        }
        return Coverage.group(stories).map { Entry(headline: $0, tag: pick.tag, major: false) }
    }
}

// TitleBar draws a window's title bar with its three buttons.
struct TitleBar: View {
    // title names the app.
    let title: String
    // background fills the bar.
    let background: Color
    // foreground draws the title.
    let foreground: Color

    // body draws the buttons on the left and the title centered.
    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 12, height: 12)
                Spacer()
            }
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(foreground.opacity(0.8))
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(background)
    }
}

// Deployboard is a made-up dark deploy dashboard with the band across its top in teal.
struct Deployboard: View {
    // entries feed the band.
    let entries: [Entry]

    // background, panel, foreground, and teal are the dashboard's colors.
    static let background = Color(red: 0.07, green: 0.09, blue: 0.11)
    static let panel = Color(red: 0.11, green: 0.14, blue: 0.17)
    static let foreground = Color(red: 0.88, green: 0.93, blue: 0.95)
    static let teal = Color(red: 0.18, green: 0.80, blue: 0.74)

    // body draws the title bar, the band, a row of stats, and the latest deploys.
    var body: some View {
        VStack(spacing: 0) {
            TitleBar(title: "Deployboard", background: Self.panel, foreground: Self.foreground)
            NewsBand(
                entries: entries,
                theme: BandTheme(
                    background: Self.background, foreground: Self.foreground, accent: Self.teal, tile: Self.panel,
                    bell: Self.teal))
            HStack(spacing: 14) {
                stat("Services", "12", "healthy")
                stat("Deploys", "4", "today")
                stat("Alerts", "0", "open")
                stat("p95 latency", "182", "ms")
            }
            .padding(16)
            VStack(spacing: 0) {
                deploy("api-prod", "v2.14.0", "2 min ago")
                deploy("web-edge", "v8.3.1", "9 min ago")
                deploy("billing-worker", "v1.6.2", "41 min ago")
            }
            .background(Self.panel)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding([.horizontal, .bottom], 16)
        }
        .background(Self.background)
    }

    // stat draws one stat tile: a label over a value and its unit.
    func stat(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Self.foreground.opacity(0.55))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(.system(size: 28, weight: .medium)).foregroundStyle(Self.foreground)
                Text(unit).font(.system(size: 12)).foregroundStyle(Self.foreground.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Self.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // deploy draws one deploy row: the service, its version, and when it went out.
    func deploy(_ name: String, _ version: String, _ when: String) -> some View {
        HStack {
            Circle().fill(Self.teal).frame(width: 8, height: 8)
            Text(name).font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(Self.foreground)
            Spacer()
            Text(version).font(.system(size: 12, design: .monospaced)).foregroundStyle(Self.foreground.opacity(0.6))
            Text(when).font(.system(size: 12)).foregroundStyle(Self.foreground.opacity(0.5))
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
    }
}

// Fieldbook is a made-up light notes app with the band across its top in rust on cream.
struct Fieldbook: View {
    // entries feed the band.
    let entries: [Entry]

    // cream, side, ink, and rust are the notes app's colors.
    static let cream = Color(red: 0.98, green: 0.96, blue: 0.91)
    static let side = Color(red: 0.94, green: 0.91, blue: 0.84)
    static let ink = Color(red: 0.20, green: 0.17, blue: 0.14)
    static let rust = Color(red: 0.72, green: 0.33, blue: 0.17)

    // body draws the title bar, the band, the notebook list, and an open note.
    var body: some View {
        VStack(spacing: 0) {
            TitleBar(title: "Fieldbook", background: Self.side, foreground: Self.ink)
            NewsBand(
                entries: entries,
                theme: BandTheme(
                    background: Self.cream, foreground: Self.ink, accent: Self.rust, tile: Self.ink,
                    bell: BandTheme.paper))
            Rectangle().fill(Self.ink.opacity(0.08)).frame(height: 1)
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("NOTEBOOKS").font(.system(size: 11, weight: .semibold)).foregroundStyle(Self.ink.opacity(0.5))
                    Text("Garden").font(.system(size: 13, weight: .semibold)).foregroundStyle(Self.rust)
                    ForEach(["Recipes", "Reading", "Trips"], id: \.self) { name in
                        Text(name).font(.system(size: 13)).foregroundStyle(Self.ink)
                    }
                    Spacer()
                }
                .padding(16)
                .frame(width: 180, alignment: .leading)
                .frame(maxHeight: .infinity)
                .background(Self.side)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Spring garden plan").font(.system(size: 22, weight: .semibold, design: .serif))
                        .foregroundStyle(Self.ink)
                    Text(
                        "Tomatoes go in after the last frost, along the south fence. Beans climb the old trellis, and "
                            + "the herbs stay in pots by the kitchen door so they are easy to reach."
                    )
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(Self.ink.opacity(0.85))
                    .lineSpacing(4)
                    Spacer()
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 170)
        }
        .background(Self.cream)
    }
}

// Scene lays the two windows over a soft desktop gradient, the light one overlapping the dark one's lower edge.
struct Scene: View {
    // entries feed both bands.
    let entries: [Entry]

    // size is the picture's size in points.
    static let size = CGSize(width: 1448, height: 828)

    // body draws the backdrop and both windows.
    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(red: 0.36, green: 0.42, blue: 0.55), Color(red: 0.62, green: 0.55, blue: 0.62)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            window(Deployboard(entries: entries)).offset(x: 48, y: 44)
            window(Fieldbook(entries: entries)).offset(x: 160, y: 432)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    // window gives an app its width, rounded corners, and drop shadow.
    func window(_ app: some View) -> some View {
        app.frame(width: 1240)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
    }
}

// render draws the scene in an offscreen window, waits for the ticker to fill, and writes a PNG at twice the
// point size to the path.
@MainActor
func render(to path: String) throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let size = NSSize(width: Scene.size.width, height: Scene.size.height)
    let window = NSWindow(
        contentRect: NSRect(origin: NSPoint(x: -20000, y: -20000), size: size), styleMask: [.borderless],
        backing: .buffered, defer: false)
    let host = NSHostingView(rootView: Scene(entries: entries(now: Date())))
    host.frame = NSRect(origin: .zero, size: size)
    window.contentView = host
    window.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(6))
    host.layoutSubtreeIfNeeded()
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width) * 2, pixelsHigh: Int(size.height) * 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)
    else {
        throw CocoaError(.fileWriteUnknown)
    }
    rep.size = size
    host.cacheDisplay(in: host.bounds, to: rep)
    window.close()
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: URL(fileURLWithPath: path))
}

do {
    try render(to: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "crierkit.png")
} catch {
    FileHandle.standardError.write(Data("showcase: render failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
