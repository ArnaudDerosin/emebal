# Emebal

**Double-press ⌘C on any text and read it in your language.**

Emebal is a small macOS menu-bar app for instant, natural translations. Select
text anywhere, press ⌘C twice, and a floating panel shows two translations side
by side: Apple's on-device translation, available instantly, and Claude's, more
natural, a few seconds later. The source language is detected automatically, and
you choose the language you want to read in.

> **Status:** early development. The first working version is here: double ⌘C,
> Apple and Claude side by side, language detection and a target-language menu.

## Why "Emebal"?

The name comes from the Sumerian **eme-bal**, "interpreter", literally
*"tongue-turner"* (*eme*, "tongue", and *bal*, "to turn, to cross over").
It is one of the oldest known words for a translator: interpreters with this
title appear in Mesopotamian records from over 4,000 years ago.

## Planned features

- **Double ⌘C** anywhere to translate the selected text
- **Automatic source-language detection**, done locally with Apple's
  NaturalLanguage framework
- **Target language of your choice**, remembered between launches
- **Two translations side by side**, each with its own Copy button: Apple
  (instant, on-device) and Claude (natural, keeps the original tone, and leaves
  code, identifiers, file paths and URLs untouched, which makes it useful for
  code reviews and technical discussions)
- **Turn either one off** in Settings to show only Apple or only Claude
- **Floating panel** near the cursor

## Translation engines

| | Apple Translation | Claude Code |
|---|---|---|
| Speed | Instant | A few seconds |
| Runs | On your Mac, offline | Through your signed-in Claude Code |
| Cost | Free | Counts toward your own Claude account |
| Style | More literal | Natural, keeps tone and code |

- **Apple Translation**: built into macOS, on-device and free. Languages may
  need to be downloaded once in System Settings.
- **Claude Code**: if you have [Claude Code](https://claude.com/claude-code)
  installed and signed in, Emebal runs it locally to translate. Usage counts
  toward your own Claude account.

Emebal is an independent project and is not affiliated with or endorsed by
Anthropic.

## Requirements

- macOS 15 or later (for Apple Translation)
- Xcode 16 or later (Swift 6) to build from source

## Build and run

```sh
./scripts/build-app.sh
open build/Emebal.app
```

To work on the code, open the folder in Xcode (`open Package.swift`) or run
`swift build`.

On first use, macOS will ask you to allow Emebal in
**System Settings → Privacy & Security → Accessibility**. Emebal needs this to
detect the double ⌘C shortcut. Without it, you can still use
**Translate Clipboard** from the menu-bar icon.

Builds are signed ad hoc, so after rebuilding you may need to turn Emebal off
and on again in the Accessibility list.

## Tests

```sh
swift test                        # fast tests only
EMEBAL_LIVE_TESTS=1 swift test    # also runs a real translation through Claude Code
```

## License

[MIT](LICENSE)
