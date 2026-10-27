# Paper Reader

A native macOS reader with a figure view and caption on the left and an independently scrolling PDF on the right. Build using the instructions below, then double-click **Paper Reader.app** or **Launch Paper Reader.command**.

1. Open a local PDF.
2. Scroll freely to any figure in the left PDF pane.
3. Type `2`, `Fig. 2`, `Figure 2`, or a panel such as `2b` into **Find figure**.
4. The original PDF on the right jumps to the first matching figure reference, highlighted light lilac. Use **Previous mention** / **Next mention** to navigate. Enter or **Find passages** also runs the search. The two PDF views scroll independently; searching never moves the left view.
5. Click a figure reference in the right PDF to open its detected figure page on the left. The right view stays in place. Native internal PDF links also open in the left view.
6. Captions are detected using PDF line positions and appear below the PDF. Panel searches use the parent figure caption. If detection fails, select caption text in either PDF and click **Use selected PDF text as caption**. Drag the dividers to resize the panes.

All PDF processing stays on your Mac. Search uses explicit references, not semantic inference. Caption detection is approximate. Grouped references and discussion boundaries are not fully supported yet. Scanned PDFs need OCR. Caption edits are not saved between sessions; manual highlights autosave to the PDF.

## Build

Requires Apple's Swift compiler (Xcode Command Line Tools).

```sh
./scripts/build-app.command
```

## Search checks

```sh
swiftc Search.swift CaptionDetector.swift tests/main.swift -o tests/search-checks -framework NaturalLanguage -framework PDFKit -framework CoreText
./tests/search-checks
```

Figure-type hints are learned across the whole document: prefixes occurring more than three times use lighter clay-pink highlights. Extended Data and Supplemental/Supplementary variants share counts; unfamiliar recurring prefixes can also be flagged. Common words such as “see” and “in” are ignored. The footer lists learned prefixes and counts. This is a heuristic and may misclassify repeated wording.

The main panes use equal-width constraints by default. Drag the middle divider to change the proportion; double-click it to restore 50/50.

Both **Find figure** and **Find text** are above the right PDF and navigate only that pane. Text search is case-insensitive and updates as you type; use the shared Previous/Next mention controls to move between matches in the most recently used search. Figure highlights stay visible during text searches.

## Manual highlighting

Highlight controls are in the top right, beside the appearance toggle.

- Select text in either PDF, choose a color, and click **Highlight** (⌘⇧H).
- With no text selected, click **Highlight** to turn on highlighting mode. Each new text selection is highlighted until you toggle it off.
- With no highlight chosen, click **Remove** to turn on removal mode. Click manual highlights to delete them until you toggle it off.
- Click a manual highlight then **Remove**, or Option-click it, for a single removal.
- ⌘Z undoes highlight changes; ⌘⇧Z redoes them.

Changes autosave directly to the opened PDF after a short delay; ⌘S saves immediately. Autosave includes highlight additions, removals, undo, and redo. Writes are atomic. A failed save leaves edits in memory and shows an error; closing retries before offering to discard. Automatic figure-reference overlays are temporary and are not saved.

Highlight checks:

```sh
swiftc HighlightStore.swift tests/highlights/main.swift -o tests/highlight-checks -framework AppKit -framework PDFKit -framework CoreText
./tests/highlight-checks
```

## Build and update the installed app

Run `./scripts/build-app.command` to compile, sign, and update both the project bundle and `~/Applications/Paper Reader.app`. Quit and reopen any running copy to load the new build. Use this script for future updates so the installed copy stays current.
