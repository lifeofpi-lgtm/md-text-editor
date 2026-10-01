# MDmaster

A native macOS app for writing and creating Markdown files. Think TextEdit, but modern, and it
writes `.md`.

## What it is for

MDmaster is for people who write in Markdown and want a calm, Mac-native place to do it. You type
plain Markdown and the editor styles it as you go (the iA Writer model), so what you see is what
the file contains. There is no hidden database or proprietary format: every sheet is a real
file in a real folder, so Finder, Git and any other editor keep working with your writing.

- **Write:** distraction-free Writing Mode, typewriter scrolling, focus dimming and word goals
- **Organise:** point it at a folder and browse, search and sort your sheets
- **Create:** a formatting toolbar and shortcuts for headings, lists, links and more
- **Share:** export to HTML, PDF and DOCX

## Features

- Live styled markdown: headings, bold, italic, inline code, links, lists, checkboxes,
  blockquotes, fenced code, tables (monospace alignment)
- Library window: pick a folder, browse its subfolders and sheets (`.md`, `.markdown`,
  `.txt`, `.rtf`), search by name and content, sort by modified date or name
- Autosave, plus automatic refresh when files change outside the app
- Customizable toolbar for formatting, new sheet or folder, word goal, export and share
- Writing Mode (full screen, no chrome), typewriter scrolling, focus dimming
- Word goals, word and character counts, reading time
- Spelling and grammar checking (Apple's, skipped inside code)
- Export to HTML, PDF and DOCX
- Light and dark mode

## Requirements

- macOS 14 or later
- Xcode Command Line Tools (`xcode-select --install`) to build
- Optional: [pandoc](https://pandoc.org) (`brew install pandoc`) for DOCX export

## Build

```sh
./build.sh          # release build -> outputs/MDmaster.app
./build.sh run      # build and launch
```

The app is ad-hoc signed, not notarized. On first launch, right-click the app and choose
Open to get past Gatekeeper.

## DOCX export

DOCX export uses `pandoc` if it is installed. To apply your own template, set a converter
script in Preferences > Export. It is called as `script input.md output.docx`.

## Status

In active development. Rich text (`.rtf`) editing is not finished: `.rtf` sheets are
listed but not yet editable. Design decisions are logged in [decisions.md](decisions.md).

## License

[MIT](LICENSE)
