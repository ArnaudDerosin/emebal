# Changelog

All notable changes to Emebal are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-10-21

The first release of Emebal: select text anywhere, press ⌘C twice, and read
it in your language.

### Added

- Double ⌘C in any app opens a floating panel with the translation.
- Apple's on-device translation and Claude's translation, side by side, each
  with a Copy button. Either can be turned off.
- Claude translations run through your own Claude Code: no credentials in
  Emebal, and usage counts toward your own Claude plan or API key.
- Claude plan usage under the Claude translation: session and weekly usage,
  and when the session resets.
- The original text in its own column, which can be hidden.
- Automatic source-language detection on your Mac, which ignores code, so
  technical messages full of identifiers are detected correctly.
- Target language picked from the panel header and remembered.
- A resizable panel that fits its content, opens near the cursor, and closes
  when you click outside it (or stays open, if you prefer).
- Translate Clipboard from the menu bar, without the shortcut.
- Open at Login.
- The interface in English and Japanese, following your Mac's language.
- `./scripts/build-app.sh --install` builds Emebal and installs it in
  Applications.

[Unreleased]: https://github.com/ArnaudDerosin/emebal/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ArnaudDerosin/emebal/releases/tag/v0.1.0
