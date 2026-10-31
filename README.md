# Shiori

A local-only novel reader for iPhone, written in SwiftUI. 一个只读本地书的 iPhone 小说阅读器。

Shiori reads your own EPUB, TXT and PDF files: there is no catalogue, no account and no
server. It is built for long Chinese web novels (thousands of chapters) and tuned for the
iPhone 17 Pro Max.

**Status:** M1 shipped as TestFlight build 1: import EPUB and TXT, a plain shelf, and a
scroll reader that remembers your place. M2 (the look) is next. See
[the roadmap](docs/roadmap.md).

## Planned

- **Shelf:** a 3D spine carousel above a list or grid, with series, categories, tags,
  search and reading history.
- **Import:** from Files, a watched folder or the share sheet. Re-downloaded books update
  in place and keep your progress and notes.
- **Reader:**
  - scroll or pages, with a paragraph-relay turn, Apple's page curl and a 3D paper turn
  - full typography and paper themes
  - notes, highlights, bookmarks and search
  - read-aloud with on-device voices
- **Reading statistics.** Chinese and English UI.

## Docs

- [Design spec](docs/superpowers/specs/2026-10-31-shiori-design.md)
- [Roadmap](docs/roadmap.md)
- [Plans](docs/superpowers/plans/)
- [Third-party code](docs/THIRD_PARTY.md)

## Building

There is no Mac in this project's loop. GitHub Actions builds, tests and screenshots
every push, and signed builds go to TestFlight. See `CLAUDE.md`.

## License

[MIT](LICENSE). Shiori is written from scratch. It borrows UI ideas, not code, from the
reader app its author used before.
