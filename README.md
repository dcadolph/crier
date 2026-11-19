<p align="center">
  <img src="art/banner.png" alt="Crier" width="100%">
</p>

# Crier

Crier is a quiet news ticker for the macOS menu bar. Headlines scroll in the bar's empty middle, or in a
thin strip just below it, and a notification arrives only when a story is truly major.

Crier is free. It is a work in progress.

## What it does

- Reads about thirty news feeds across politics, world affairs, economics, technology, science, movies,
  music, video games, pop culture, and sports, plus any RSS or Atom feeds you add.
- Groups the same story from different outlets and ranks stories by how many outlets carry them, weighed
  by how much of each topic you want. Each topic is set to More, Normal, Less, Major only, or Off. Out of
  the box it leans toward world affairs, politics, tech, and science, keeps movies, music, and games in
  the mix lower down, and holds pop culture and sports back until a story is major.
- Calls a story major when six or more outlets carry it, or twelve for a topic set to Less. Major
  stories get a red dot, and the newest ones can send a notification, with quiet hours, a daily cap,
  and no repeats.
- Keeps the teams and subjects you follow in the ticker.
- Fills the open menu bar with the ticker by default, or sets it at a fixed width at the center, left of
  center, or right of center. It stays clear of the status icons. A filling ticker runs on both sides of
  the notch and of the clock from Fuginaut, with headlines passing behind them. A fixed width ticker steps
  around them.
- Opens a window with a news band on top: the biggest stories as cards that take turns in rotating
  columns, each naming its outlet, how many outlets carry it, and how old it is, with the ticker running
  underneath. The full headline list sits below the band.

Hover over the ticker to hold it still, both sides at once when it is split. Click a headline to open it.

<p align="center">
  <img src="art/news-band.png" alt="The news band: three major stories as cards above the ticker" width="100%">
</p>

<p align="center">
  <img src="art/split-ticker.png" alt="The ticker in the menu bar, running on both sides of a clock" width="100%">
</p>

## Install

Crier needs macOS 14 or later. With Homebrew:

```sh
brew install --cask dcadolph/tap/crier
```

Or download `crier_macos_universal.dmg` from the
[latest release](https://github.com/dcadolph/crier/releases/latest), open it, and drag Crier to
Applications. Releases are signed with a Developer ID and notarized by Apple.

## Verify a download

Each release carries `SHA256SUMS` with a keyless cosign signature and a build provenance attestation.

```sh
cosign verify-blob SHA256SUMS --signature SHA256SUMS.sig --certificate SHA256SUMS.pem \
  --certificate-identity-regexp '^https://github.com/dcadolph/crier/\.github/workflows/release\.yml@refs/tags/v' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
shasum -a 256 -c SHA256SUMS --ignore-missing
gh attestation verify crier_macos_universal.dmg --repo dcadolph/crier
```

## Build from source

```sh
make run
```

`make app` builds `Crier.app` in `.build`, and `make run` builds it and opens it.

## Settings

Open Settings from the bell in the menu bar. The ticker's place, position, width, speed, and color, how
much of each topic you want and which single feeds to read, the colors of the news window, followed
teams, your own feeds, and alert rules all apply right away. Hover over any control to see what it
changes. A feed that fails to load names the reason under its name.

With Accessibility permission, Crier reads where the frontmost app's menus end, so a ticker that fills
the bar never covers them. Without it, Crier keeps a fixed amount of room for the menus, which you can
change in Settings.

## CrierKit

The news engine and its SwiftUI views live in the `CrierKit` library, so another app can show the same
ticker and news band. Add this package as a dependency and use `News`, `TickerView`, `NewsBand`, and
`HeadlineList`. The cards, their rotation, the progress line, and the ticker all come from CrierKit. A
host app hands in its own colors, and the band takes them on.

```swift
import CrierKit
import SwiftUI

struct Headlines: View {
    @State private var news = News()

    var body: some View {
        NewsBand(
            entries: news.entries,
            theme: BandTheme(background: .black, foreground: .white, accent: .orange, tile: .black, bell: BandTheme.gold),
            rotation: .seconds(30)
        )
        .onAppear { news.start() }
        .onDisappear { news.stop() }
    }
}
```

## Development

```sh
make build    # debug build
make test     # offline tests
make lint     # swift-format, strict
make format   # format in place
```

## License

MIT. See [LICENSE](LICENSE).
