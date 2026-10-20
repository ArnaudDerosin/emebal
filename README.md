# Emebal

**Double-press ⌘C on any text and read it in your language.**

Emebal is a small macOS menu-bar app for instant, natural translations. Select
text anywhere, press ⌘C twice, and a floating panel shows the translation. The
source language is detected automatically, and you choose the language you want
to read in.

> **Status:** early development. The menu-bar shell runs; translation is not
> implemented yet.

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
- **Natural translations** that keep the original tone, while leaving code,
  identifiers, file paths and URLs untouched, which makes it useful for code
  reviews and technical discussions
- **Floating panel** near the cursor, with Copy and Close

## Translation backends

- **Anthropic API** (recommended): add your Anthropic API key in Settings.
- **Claude Code CLI**: if you have [Claude Code](https://claude.com/claude-code)
  installed and signed in, Emebal can run it locally to translate. Usage counts
  toward your own Claude account.

Emebal is an independent project and is not affiliated with or endorsed by
Anthropic.

## Requirements

- macOS 14 or later
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
detect the double ⌘C shortcut.

## License

[MIT](LICENSE)
