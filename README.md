<p align="center">
  <img src="art/banner.png" alt="Crier" width="100%">
</p>

# Crier

Crier is a quiet news ticker for the macOS menu bar. Headlines scroll in the bar's empty middle, or in a
thin strip just below it, and a notification arrives only when a story is truly major.

Crier is free. It is a work in progress.

## What it does

- Reads about twenty news feeds across politics, world affairs, economics, technology, and science, plus
  any RSS or Atom feeds you add.
- Groups the same story from different outlets and ranks stories by how many outlets carry them.
- Calls a story major when six or more outlets carry it. Major stories get a red dot, and the newest ones
  can send a notification, with quiet hours, a daily cap, and no repeats.
- Keeps pop culture and sports out of the ticker unless a story is major, and keeps the teams and topics
  you follow in it.
- Places the ticker at the center, left of center, or right of center of the menu bar, or fills the open
  bar. It steps around the notch and around the clock from Fuginaut, and stays clear of the status icons.
- Opens a window with the top stories in rotating columns over the full headline list.

Hover over the ticker to hold it still. Click a headline to open it.

## Install

Crier needs macOS 14 or later. Build it from source:

```sh
make run
```

`make app` builds `Crier.app` in `.build`, and `make run` builds it and opens it.

## Settings

Open Settings from the bell in the menu bar. The ticker's place, position, width, speed, and color, the
topics and single feeds, the colors of the news window, followed teams, your own feeds, and alert rules
all apply right away.

With Accessibility permission, Crier reads where the frontmost app's menus end, so a ticker that fills
the bar never covers them. Without it, Crier keeps a fixed amount of room for the menus, which you can
change in Settings.

## CrierKit

The news engine and its SwiftUI views live in the `CrierKit` library, so another app can show the same
ticker and news band. Add this package as a dependency and use `News`, `TickerView`, `NewsBand`, and
`HeadlineList`.

## Development

```sh
make build    # debug build
make test     # offline tests
make lint     # swift-format, strict
make format   # format in place
```

## License

MIT. See [LICENSE](LICENSE).
