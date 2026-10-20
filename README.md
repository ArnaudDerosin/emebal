<p align="center">
  <img src=".github/assets/banner.png" alt="Emebal: Select. ⌘C ⌘C. Understood." width="100%">
</p>

<p align="center">
  <strong>Double-press ⌘C on any text and read it in your language.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-B5713F" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/status-early%20development-D9BF94" alt="Status: early development">
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="#getting-started">Getting started</a> ·
  <a href="#why-emebal">Why “Emebal”?</a>
</p>

---

Emebal is a small macOS menu-bar app for instant, natural translations. Select
text anywhere, press **⌘C twice**, and a floating panel shows two translations
side by side: Apple's on-device translation, available instantly, and Claude's,
more natural, a few seconds later.

## Features

- **Double ⌘C anywhere** to translate the selected text, in any app
- **Automatic source-language detection**, done locally with Apple's
  NaturalLanguage framework
- **Target language of your choice**, picked from the panel header and
  remembered between launches
- **Two translations side by side**, each with its own Copy button
- **Turn either engine off** to show only Apple or only Claude, and choose the
  Claude model
- **Floating panel** that opens near the cursor and stays until you close it
- **Translate Clipboard** from the menu-bar icon, without the shortcut

## How it works

| | Apple Translation | Claude |
|---|---|---|
| Speed | Instant | A few seconds |
| Runs | On your Mac, offline | Through your own Claude Code |
| Cost | Free | Counts toward your own Claude account |
| Style | More literal | Natural, keeps the tone, leaves code untouched |

- **Apple Translation** is built into macOS, on-device and free. Languages may
  need to be downloaded once in System Settings.
- **Claude** translations run the [Claude Code](https://claude.com/claude-code)
  CLI installed on your Mac (`claude -p`). Emebal never sees your credentials:
  Claude Code uses your own sign-in, and usage counts toward your own Claude
  plan or API key. Claude keeps the original tone and leaves code, identifiers,
  file paths and URLs as they are, which makes it handy for code reviews and
  technical discussions.

## Getting started

### Requirements

- macOS 15 or later (for Apple Translation)
- Xcode 16 or later (Swift 6) to build from source
- Optional: [Claude Code](https://claude.com/claude-code), installed and signed
  in, for Claude translations

### Build and run

```sh
git clone https://github.com/ArnaudDerosin/emebal.git
cd emebal
./scripts/build-app.sh
open build/Emebal.app
```

To work on the code, open the folder in Xcode (`open Package.swift`) or run
`swift build`.

### Allow Accessibility

On first use, macOS asks you to allow Emebal in
**System Settings → Privacy & Security → Accessibility**. Emebal needs this to
detect the double ⌘C shortcut. Without it, you can still use
**Translate Clipboard** from the menu-bar icon.

<details>
<summary>The permission stops working after a rebuild?</summary>

<br>

macOS ties the Accessibility permission to the app's signature. Builds are
signed ad hoc by default, which changes on every build. To fix it once:

```sh
tccutil reset Accessibility io.github.arnaudderosin.emebal
```

then open the app again and allow it. To keep the permission across rebuilds,
create a self-signed code-signing certificate (Keychain Access → Certificate
Assistant → Create a Certificate…, Identity Type **Self Signed Root**,
Certificate Type **Code Signing**) and build with it:

```sh
EMEBAL_SIGN_IDENTITY="Emebal Local Signing" ./scripts/build-app.sh
```

</details>

### Tests

```sh
swift test                        # fast tests only
EMEBAL_LIVE_TESTS=1 swift test    # also runs a real translation through Claude Code
```

## Why “Emebal”?

The name comes from the Sumerian **eme-bal** (𒅴𒁄), "interpreter", literally
*"tongue-turner"*:

| Sign | Reading | Meaning |
|---|---|---|
| 𒅴 | *eme* | "tongue", written as the sign for "mouth" with ME inside it |
| 𒁄 | *bal* | "to turn, to cross over" |

It is one of the oldest known words for a translator: interpreters with this
title appear in Mesopotamian records from over 4,000 years ago. The icon's two
wedges, the basic strokes of cuneiform, point in opposite directions: one
language turning into another.

## License

[MIT](LICENSE)

Emebal is an independent project and is not affiliated with or endorsed by
Anthropic or Apple.
