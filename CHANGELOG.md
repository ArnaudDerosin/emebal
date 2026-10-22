# Changelog

All notable changes to Emebal are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Text Size in the menu: Small, Medium or Large text in the translation panel.
- When Claude Code isn't installed or isn't signed in, the Claude column says
  so, with an Install Claude Code… or Open Terminal button.

### Changed

- Larger, easier-to-read text in the translation panel (the new Medium size).
- The shortcut is described as ⌘C C (hold ⌘ and press C twice), which is how
  it's used.
- The menu-bar menu stays open while you change settings, like the Wi-Fi and
  Sound menus, and groups them under Translation, Columns and Panel.
- The Claude plan usage now sits next to the Claude title instead of next to
  the Copy button. It shows right away when the panel opens (the usage from
  the past 5 minutes, or a placeholder until numbers arrive), updates before the
  translation is done with a smooth animation, and hides numbers from a window
  that has already reset.
- Languages are named in Emebal's language, followed by their own name: for
  example "Japanese (日本語)" when Emebal is in English.

### Fixed

- Apple's translation could stay on "Translating…" after changing the target
  language, especially when going back to a language used before.
- Picking the language that's already selected no longer translates the text
  again.
- The panel stays on screen when a long translation makes it grow: it no longer
  slides under the Dock or past the edges. With a single column it's also wider,
  so long translations don't make it as tall.
- Changing the language from the menu bar now translates the open panel's text
  again, as changing it from the panel does.

## [0.1.0] - 2026-10-21

The first release of Emebal: select text anywhere, hold ⌘ and press C twice
(⌘C C), and read it in your language.

### Added

- ⌘C C (hold ⌘, press C twice) in any app opens a floating panel with the
  translation.
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
