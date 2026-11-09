# PM2 Desktop

Native macOS app (SwiftUI) to control [PM2](https://pm2.keymetrics.io/) process manager.

## Features

- **Auto-detect** Node.js and PM2 across common install locations: Homebrew, nvm, fnm, Volta, bun, `~/.npm-global`, system paths.
- **Guided install** — if Node.js is missing, installs it via Homebrew or the official nodejs.org `.pkg` (admin prompt). If PM2 is missing, installs it via `npm install -g` (falls back to `~/.npm-global` on permission errors).
- **Process list** — name, PID, CPU, memory, uptime, restart count. Live refresh every 5 seconds, name filter.
- **Create** — name + start target file (or command such as `npm`), working directory, arguments, interpreter, optional build command that runs before start, auto-restart toggle.
- **Control** — start, stop, restart, delete (with confirmation), view logs (stdout + stderr tail).

## Requirements

- macOS 13+
- Swift 5.9+ (Xcode Command Line Tools)

## Build & run

```bash
swift run            # development build
./make-app.sh        # release .app + .dmg installer in build/
open build/PM2Desktop.dmg   # drag PM2 Desktop into Applications
```

## Notes

- GUI apps do not inherit your shell PATH, so the app searches standard locations itself and injects that PATH into every command it runs. If your node/pm2 live somewhere unusual, add them via a supported version manager or symlink into `/usr/local/bin`.
- PM2 processes are managed by the PM2 daemon for your user; they keep running after the app closes, exactly like using the CLI.
- `pm2 save` / `pm2 startup` setup is not handled — run those in a terminal if you need resurrection on boot.

## Layout

```
Sources/PM2Desktop/
├── PM2DesktopApp.swift       # @main, WindowGroup
├── Models/PM2Process.swift   # pm2 jlist decoding
├── Services/ShellRunner.swift # PATH discovery, async shell exec
├── Services/PM2Store.swift   # detection, install, CRUD, logs
└── Views/                    # setup, list, add sheet, logs sheet
```
