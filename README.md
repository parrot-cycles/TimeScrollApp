# Scrollback

A macOS screen capture and intelligent search app that automatically captures screenshots and lets you search through your visual history.

**Fork of**: [TimeScroll](https://timescroll.muzhen.org/) by [XInTheDark](https://github.com/XInTheDark) — renamed to Scrollback.

This fork adds ScreenMemory migration tools, UI improvements, and safety enhancements.

## Download

Pre-built DMG available in [Releases](https://github.com/parrot-cycles/Scrollback/releases).

## What's New in v1.1.0

### ScreenMemory Import
- Import screenshots and OCR text from ScreenMemory app
- Supports both Copy (for external drives) and Move (saves space) modes
- Two-phase import: OCR-indexed screenshots with text, then orphan files on disk
- Duplicate detection, app usage matching, progress tracking
- Rebuild from disk button to re-index files after restore

### Calendar Navigation
- Monthly calendar picker with red-highlighted days that have content
- Bottom navigation bar: prev/next day, prev/next snapshot, date picker
- Click date to open calendar, click a day to jump to it
- Today button in calendar

### Redesigned Toolbar
- Icon-only toolbar buttons (capture, filters, vault, zoom, live)
- Cleaner search field with clear (X) button
- Back arrow to return to search results after viewing a snapshot
- Cmd+F to focus search field, Escape to go back

### Smart Filters
- Apple Mail-style filter builder in filter popover
- Add/remove condition rows with +/- buttons
- Fields: Text, App Name, Year, Month, Day
- Operators: contains, not contains, is, is not
- Match all/any toggle (AND vs OR logic)

### Search Improvements
- Total result count displayed in search header
- Search method indicator badge: FTS (blue), AI (purple), AI->FTS (orange)
- AI search falls back to FTS when no embedding results found
- Right-click context menu on search results and screenshots
- Reveal in Finder, Open in Preview, Copy Image/Text/Path

### Safety & Permissions
- Default retention changed from 30 days to 999999 days
- Backup enabled by default
- File deletion uses Trash instead of permanent delete
- Permission check works with ad-hoc signed builds (probes SCShareableContent)
- Permissions status in General settings with Grant/Refresh buttons
- Onboarding auto-refreshes permission status every 3 seconds

### Other
- Capture interval range expanded: 1s to 120s in 1-second steps
- Fixed pre-existing broken tests (TimelineModeTests, SearchQueryTests, EmbeddingServiceTests)
- 6 unit tests for import functionality

## Roadmap (v1.2.0)

- Multi-Mac sync (capture on each Mac, aggregate in one viewer)
- Text selection on screenshots (OCR bounding box overlay)
- Homebrew cask install (`brew install --cask scrollback`)
- Enhanced search results navigation

## Building from Source

The Xcode scheme and project file still use the name `Scrollback` — only the user-visible app name and bundle ID were renamed.

```bash
xcodebuild -project app/Scrollback.xcodeproj -scheme Scrollback -configuration Release build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM=""

# Re-sign with correct bundle ID for permissions to work
codesign --force --sign - --identifier "com.parrotcycles.scrollback" \
  ~/Library/Developer/Xcode/DerivedData/Scrollback-*/Build/Products/Release/Scrollback.app

cp -R ~/Library/Developer/Xcode/DerivedData/Scrollback-*/Build/Products/Release/Scrollback.app /Applications/
```

## Credits

- Original app by [Muzhen Gaming / XInTheDark](https://github.com/XInTheDark)
- Fork maintained by [parrot-cycles](https://github.com/parrot-cycles)
- Built with assistance from Claude (Anthropic)

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE)
