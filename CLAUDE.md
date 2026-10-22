# Emebal

macOS menu-bar translator (SwiftUI, Swift 6, SwiftPM, macOS 15+). ⌘C C (hold
⌘, press C twice) shows Apple's on-device translation and Claude's (through the user's own
`claude -p`) side by side.

## Changelog and releases

- For every change a user would notice (feature, fix, visible behavior or
  wording), add a line under `## [Unreleased]` in `CHANGELOG.md`, in the same
  commit, under `### Added`, `### Changed` or `### Fixed`. Write it for users,
  not developers. Internal changes (refactoring, tests, scripts, docs for
  contributors) don't go in the changelog.
- Release with `./scripts/release.sh X.Y.Z`, never by hand. Semantic
  versioning: new features → minor (0.2.0), fixes only → patch (0.1.1). The
  script asks for confirmation before publishing; only release when the user
  asks.

## Interface text and translations

- Every user-facing string is localized: SwiftUI literals, or
  `String(localized:)` for strings built in code. Build whole sentences with
  interpolation, never by joining fragments, so other languages can reorder.
- After changing interface text, run `./scripts/update-strings.sh`, then add or
  update the Japanese in `Resources/Localization/ja.lproj/Localizable.strings`
  (natural Japanese, macOS's own terms). `swift test` checks every language
  against English.

## Docs

- `README.md` and `README.ja.md` mirror each other: update both. Japanese
  paragraphs stay on one line (a line break inside a paragraph shows as a
  space on GitHub), with a space between Japanese and Latin words.

## Building and installing

- `swift test` must pass. `./scripts/build-app.sh --install` builds and moves
  the app to /Applications (the only copy, so macOS shows the right icon).
- Each build has a new ad-hoc signature, which silently breaks the
  Accessibility permission (the ⌘C C shortcut). To install for testing without several
  prompts: quit Emebal, then
  `tccutil reset Accessibility io.github.arnaudderosin.emebal`, then install
  once.

## Principles

- Emebal never reads Claude credentials (Keychain, `~/.claude`): it only runs
  the user's unmodified `claude` CLI, so usage stays on their own plan.
- Commits: conventional style (`feat:`, `fix:`, `docs:`, `chore:`), short
  imperative subject.
