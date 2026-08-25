# Report

## Fix round 2 (directive)

`TextContract.directive` in `Sources/SwiftStarKit/LabeledBlockParser.swift` was rewritten to
plain prose with literal backticks (no `\u{0060}` escapes), so a chat model reading the directive
sees an unambiguous heading form: `### `app.py``.

- `swift build` → Build complete!
- `swift test --filter LabeledBlockParserTests` → 10/10 tests passed (parser unchanged).
- `TextContract.directive` no longer contains `\u{0060}` (verified via grep on the directive;
  the only remaining occurrence is an unrelated doc comment on the parser's path-normalization
  helper).
