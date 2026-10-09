# Contributing

Thanks for your interest in MonitorBar.

## Reporting bugs

Open an issue with:

- macOS version and chip (Intel / Apple Silicon)
- What you expected vs what happened
- Console output if the app crashes (`log show --last 5m --predicate 'process == "MonitorBar"'`)

## Pull requests

- Keep the zero-dependency policy: this project deliberately uses only public
  macOS APIs (Mach, IOKit, sysctl, `libproc`).
- Run `swift build` and `swift test` before opening a PR; CI runs both plus a
  full `.app` packaging pass.
- New metrics belong in `Sources/MonitorBarCore/Probes.swift` (data collection)
  surfaced through `SystemMonitor` and `PanelView` — keep those layers
  separated.
- If your change alters the panel UI, regenerate `Docs/screenshot.png` with
  `make screenshot` and the icon only if it changes (`make icon`).

## Style

- Standard Swift conventions, 4-space indentation.
- Comments explain *why* a specific API or counter was chosen — keep them.
