# SmoothTox

A minimal, modern Tox client for macOS.

![SmoothTox Preview](docs/assets/smoothtox-cover.png)

## Feature Table

| Feature | Description | Status |
|---|---|---|
| Core Tox Integration | Native integration with `libtoxcore` via C wrapper | ✅ |
| Private Messaging | End-to-end encrypted 1:1 text messaging | ✅ |
| Group Chats | Host, join, invite accept, and group messaging | ✅ |
| Group Member List | Live member display in selected group chat | ✅ |
| Voice Calls | Basic ToxAV voice call support | ✅ |
| File Transfer | Send/receive files with progress updates | ✅ |
| Avatar Sync | Profile avatar send/receive between peers | ✅ |
| Localization | JSON-based runtime localization (`en`, `tr`) | ✅ |
| Search | Peer/group list search and in-chat message search | ✅ |
| Proxy Support | Tor / SOCKS / HTTP proxy support via config | ✅ |
| Profile Storage | Encrypted profile storage with SQLite + Keychain | ✅ |
| macOS UX | Native desktop app using SwiftUI + AppKit | ✅ |

## Quick Start
```bash
brew install toxcore
swift build
swift run
```

## Build DMG
```bash
./scripts/make-dmg.sh
```

Output: `dist/SmoothTox.dmg`

## Repository
`dogujen/smoothtox`
