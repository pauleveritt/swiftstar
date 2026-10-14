# SU.13: two leftovers

A small cycle (`docs/sdd.md`): one doc, no spec. Two UI items the owner
moved in on 2026-10-14: SU.3's unverified memory-widget crash, and the
report card's wide tables at narrow widths (from AN.2's follow-ups).

## Decisions

**D1. Check the memory widget in a real Debug run: the gallery.** It flips
the fixture's GPU metrics on and off at launch when its `galleryFlipGPU`
setting names a count, as the "GPU toggle" preview does. Fixture-only: the
controller's new `replaceFixtureModel` ignores a real controller.

**D2. The report card's tables:** waits on the owner's call (below).

## Facts this rests on

- **The crash was** in SwiftUI's debug view storage when GPU metrics went
  from present to absent (SU.3's Backlog; `StatusBarView`'s "GPU toggle"
  preview). `RenderPreview` can't run it: it snapshots the first frame.
- **The tables:** the fork's macOS `TableView` puts the grid in an
  `NSScrollView` with both scrollers off (`TableView.swift:279-284`, in
  `.build/checkouts/MarkdownView`), and caps a cell at 200 pt
  (`maximumCellWidth`). A table wider than the card scrolls, but shows
  nothing that says so: it reads as clipped.

## Tasks

### Task 1: the memory widget in the gallery

**Files:** `PreviewSupport/Gallery.swift`, `EngineController.swift`
(`replaceFixtureModel`), `SwiftStarGallery/GalleryApp.swift`.

### Task 2: the report card's tables

Open, on the owner's call.

## Result

**Task 1, done 2026-10-14.** Two Debug runs of the gallery, 20 and 21
flips at 100 ms: no crash, nothing in the console. The 21st left GPU
metrics off: the status bar's memory widget gone and the inspector's GPU
memory at "—", so the flips ran. SU.3's leftover is closed.
