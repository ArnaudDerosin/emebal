<p align="center">
  <img src=".github/assets/banner.png" alt="Emebal: Select. ⌘C ⌘C. Understood." width="100%">
</p>

<p align="center">
  <strong>Select any text, hold ⌘ and press C twice, and read it in your language.</strong>
</p>

<p align="center">
  <a href="https://github.com/ArnaudDerosin/emebal/releases/latest"><img src="https://img.shields.io/github/v/release/ArnaudDerosin/emebal?color=8C4F2B" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-B5713F" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/status-early%20development-D9BF94" alt="Status: early development">
</p>

<p align="center">
  <strong>English</strong> · <a href="README.ja.md">日本語</a>
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="#getting-started">Getting started</a> ·
  <a href="#why-emebal">Why “Emebal”?</a>
</p>

---

Emebal is a minimal, fast translator that lives in your Mac's menu bar. Select
text in any app, hold **⌘** and press **C** twice (**⌘C C**): a clean panel
opens right where you are, with an **instant** translation from Apple and a **natural** one from
Claude, side by side.

No window to switch to, no pasting into a website. Select, press, read.

<p align="center">
  <img src=".github/assets/screenshot.png" alt="Emebal translating a Japanese code-review comment into English: the original text, Apple's translation and Claude's translation side by side" width="800">
</p>

## Features

- **Instant.** Apple's on-device translation appears right away, offline and
  free.
- **Natural.** Claude's translation follows: fluent, in the original tone, with
  code, file paths and URLs left untouched.
- **Fast.** Claude's translation appears as it's written, with the first words
  in about 1.5 s. Turn on **Keep Claude Ready** and they appear in about 0.9 s
  (it keeps Claude Code started, using about 270 MB of memory).
- **Better wording.** On your own draft, click **Improve** under the original:
  Claude's clearer, more natural version, in the same language and with code
  and URLs left untouched, appears in a new row below, with its translations.
- **Out of the way.** A quiet panel near the cursor that closes when you click
  elsewhere. No Dock icon, no main window.
- **Automatic.** The source language is detected on your Mac, even in technical
  messages full of code.
- **Yours to adjust.** Target language, text size, the columns to show
  (original, Apple, Claude) and the Claude model, from a simple menu.
- **Your Claude usage at a glance.** Session and weekly usage, and when the
  session resets.
- **In English and Japanese**, following your Mac's language. Also: Translate
  Clipboard from the menu bar, and Open at Login.

## How it works

| | Apple Translation | Claude |
|---|---|---|
| Speed | Instant | First words in about 1.5 s (0.9 s with Keep Claude Ready) |
| Runs | On your Mac, offline | Through your own Claude Code |
| Cost | Free | Counts toward your own Claude account |
| Style | More literal | Natural, keeps the tone, leaves code untouched |

- **Apple Translation** is built into macOS, on-device and free. Languages may
  need to be downloaded once in System Settings.
- **Claude** translations run [Claude Code](https://claude.com/claude-code),
  Anthropic's `claude` command-line tool, installed on your Mac (not the Claude
  desktop app). Emebal never sees your credentials: Claude Code uses your own
  sign-in, and usage counts toward your own Claude plan. Claude keeps the
  original tone and leaves code, identifiers, file paths and URLs as they are,
  which makes it handy for code reviews and technical discussions.

## Getting started

### Requirements

- macOS 15 or later
- Xcode 16 or later (Swift 6), to build from source
- For Claude translations (optional): [Claude Code](https://claude.com/claude-code),
  the `claude` command-line tool (not the Claude desktop app), installed and
  signed in to your Claude account (see below)

### Set up Claude (optional)

Apple Translation works out of the box. For Claude translations, install
[Claude Code](https://claude.com/claude-code) and sign in once with your Claude
account. No API key needed.

<details>
<summary>Show setup steps</summary>

<br>

1. Install Claude Code:

   ```sh
   curl -fsSL https://claude.ai/install.sh | bash
   ```

   Other ways to install (Homebrew, npm) are in the
   [Claude Code docs](https://code.claude.com/docs/en/setup).

2. Run `claude` in a terminal and sign in with your Claude account. (If you
   pay per use through the Anthropic Console instead of a subscription, an API
   key works too.)

3. Check that it works:

   ```sh
   claude -p "Say hello"
   ```

That's all: Emebal finds `claude` on its own and uses your sign-in. It never
sees your credentials, and usage counts toward your own Claude plan. If Claude
Code is missing or signed out, the Claude column says so, with a button to fix
it, and Apple's translation keeps working. You can also turn Claude off in the
menu.

</details>

### Install

**Download:** get `Emebal-x.y.z.zip` from the
[latest release](https://github.com/ArnaudDerosin/emebal/releases/latest),
unzip it and move **Emebal** to Applications. Emebal isn't notarized by Apple
yet, so the first time, macOS won't open it: go to
**System Settings → Privacy & Security** and click **Open Anyway**.

**Or build from source:**

```sh
git clone https://github.com/ArnaudDerosin/emebal.git
cd emebal
./scripts/build-app.sh --install
```

This builds Emebal, moves it to `/Applications` and opens it. Emebal lives in
the menu bar (the speech-bubble icon), not in the Dock. To have it start
automatically, turn on **Open at Login** in its menu.

To update, pull the latest changes and run the same command again. Then, in
**System Settings → Privacy & Security → Accessibility**, remove Emebal with
**−** and allow it again: each build has a new signature, so macOS doesn't
apply the old permission to it, even though the switch still shows on.

To work on the code, open the folder in Xcode (`open Package.swift`) or run
`swift build`. `./scripts/build-app.sh` without `--install` only builds
`build/Emebal.app`.

### Uninstall

1. In the menu-bar icon's menu, turn off **Open at Login** if it is on, then
   choose **Quit Emebal**.
2. Drag **Emebal** from Applications to the Trash.
3. Optionally, remove what it leaves behind:
   - Emebal in **System Settings → Privacy & Security → Accessibility**
     (select it and click **−**)
   - its preferences:
     `defaults delete io.github.arnaudderosin.emebal`

### Allow Accessibility

On first use, macOS asks you to allow Emebal in
**System Settings → Privacy & Security → Accessibility**. Emebal needs this to
detect the ⌘C C shortcut. Without it, you can still use
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
EMEBAL_SIGN_IDENTITY="Emebal Local Signing" ./scripts/build-app.sh --install
```

</details>

### Tests

```sh
swift test                        # fast tests only
EMEBAL_LIVE_TESTS=1 swift test    # also runs a real translation through Claude Code
```

### Releasing

Changes worth telling users about go under `## [Unreleased]` in
[CHANGELOG.md](CHANGELOG.md) as you make them. To publish a version:

```sh
./scripts/release.sh 0.2.0
```

It checks that `main` is clean and up to date and that the tests pass, sets the
version, dates the changelog, builds and zips the app, then, after you confirm,
tags `v0.2.0` and publishes a
[GitHub Release](https://github.com/ArnaudDerosin/emebal/releases) with the
changelog notes and the zip. Versions follow
[Semantic Versioning](https://semver.org/): `0.2.0` for new features, `0.1.1`
for fixes.

### Translations

Emebal's interface follows the language set in macOS, and falls back to
English. Each language is a folder in `Resources/Localization/`
(`en.lproj`, `ja.lproj`…) with a `Localizable.strings` file: the keys are the
English text, and the values are the translation.

To add a language, for example French:

1. Copy `ja.lproj` to `fr.lproj` and translate each value. Keep placeholders
   like `%@`; write `%1$@`, `%2$@` if the word order changes.
2. Run `swift test`: it checks that every language has all the English strings
   with the same placeholders.

After changing interface text in the code, run `./scripts/update-strings.sh`.
It regenerates the English strings from the code and lists what each language
is missing.

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
