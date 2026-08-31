# Docs. The CI build is the strict `-W` one-shot; these are for working locally.

# Rebuild the docs as you edit them, serving on http://127.0.0.1:8000
watch-docs:
    uv run --group docs sphinx-autobuild docs docs/_build/html

# One-shot strict build -- the same gate CI runs
docs:
    uv run --group docs sphinx-build -W -b html docs docs/_build/html

# Enforce docs/sdd.md's size caps: ROADMAP phase-table Direction/Status
# cells, and current plan docs directly under docs/superpowers/plans/. Archived
# plans live below that directory and are retained unchanged.
#
# Splits table rows on a backtick-depth-aware pipe scan, not a naive
# `IFS='|'` split -- a plain split mis-indexes every cell after a Direction
# or Status cell containing an inline `` `foo | bar` `` code span or a
# regex alternation like `P(A|B)`, silently checking the wrong substring
# against the cap. Found by an independent review of this exact recipe.
lint-docs:
    #!/usr/bin/env bash
    set -euo pipefail
    fail=0
    awk '
        /^\| P[0-9]/ {
            n = split($0, chars, "")
            depth = 0; cell = 0; buf = ""
            delete cells
            for (i = 1; i <= n; i++) {
                c = chars[i]
                if (c == "`") { depth = 1 - depth; buf = buf c; continue }
                if (c == "|" && depth == 0) { cells[cell] = buf; cell++; buf = ""; continue }
                buf = buf c
            }
            cells[cell] = buf
            d = cells[3]; s = cells[4]
            if (length(d) > 900) {
                printf "ROADMAP.md: Direction cell is %d chars (cap 900): %s...\n", length(d), substr(d, 1, 70)
                bad = 1
            }
            if (length(s) > 1000) {
                printf "ROADMAP.md: Status cell is %d chars (cap 1000): %s...\n", length(s), substr(s, 1, 70)
                bad = 1
            }
        }
        END { exit bad }
    ' ROADMAP.md || fail=1
    for f in docs/superpowers/plans/*.md; do
        lifecycle="$(awk -F': *' '$1 == "lifecycle" { print $2; exit }' "$f")"
        if [ -z "$lifecycle" ]; then
            echo "$f: missing lifecycle metadata (active, closed, or superseded)"
            fail=1
        elif [ "$lifecycle" != "active" ] && [ "$lifecycle" != "closed" ] && [ "$lifecycle" != "superseded" ]; then
            echo "$f: invalid lifecycle metadata: $lifecycle"
            fail=1
        elif [ "$lifecycle" = "closed" ] || [ "$lifecycle" = "superseded" ]; then
            if ! awk '/^## Result[[:space:]]*$/ { found=1 } END { exit !found }' "$f"; then
                echo "$f: $lifecycle plan is missing a ## Result section"
                fail=1
            fi
        fi

        read -r lines fenced long_fences long_lines unbalanced <<< "$(awk '
            { total++ }
            /^```/ {
                if (inside) {
                    if (count > 15) { many++; many_lines += count }
                    inside = 0; count = 0
                } else { inside = 1; count = 0 }
                next
            }
            inside { count++; fenced++ }
            END {
                if (inside) { unclosed=1; if (count > 15) { many++; many_lines += count } }
                print total, fenced + 0, many + 0, many_lines + 0, unclosed + 0
            }
        ' "$f")"
        if [ "$unbalanced" -ne 0 ]; then
            echo "$f: unbalanced fenced code block"
            fail=1
        fi
        if [ "$long_fences" -gt 0 ]; then
            echo "$f: $long_fences fence(s) exceed 15 lines ($long_lines fenced lines)"
            awk '
                /^```/ {
                    if (inside) {
                        if (NR - start - 1 > 15) printf "  lines %d-%d\n", start, NR - 1
                        inside = 0
                    } else { inside = 1; start = NR }
                }
            ' "$f"
            fail=1
        fi
        if [ "$lines" -ge 400 ] || [ $((fenced * 100)) -ge $((lines * 25)) ]; then
            echo "$f: $lines lines, $((fenced * 100 / lines))% fenced (must be under 400 lines / 25% fenced)"
            fail=1
        fi
    done
    exit $fail

# Point git at the tracked .githooks/ dir so pre-commit runs `lint-docs`
# locally (docs/sdd.md, "Standing rules": closing a phase/branch owes a
# green lint-docs, enforced mechanically, not left to memory). One-time
# per clone; `git config` writes to this repo's untracked .git/config.
install-hooks:
    git config core.hooksPath .githooks
    @echo "pre-commit will now run 'just lint-docs' on every commit."

# Fast tier: SwiftStarKit against fixtures. No model, no network, no subprocess
# (enforced by the FastTierGuard build-tool plugin on SwiftStarKitTests).
test:
    swift test

# Integration tier: real processes and files against fake engine binaries
# generated from committed captures. Same suite, marked tests enabled.
integration:
    SWIFTSTAR_INTEGRATION=1 swift test

# Build ds4-agent from the pinned submodule SHA (P1).
#
# STANDING RULE — recapture on every bump: whenever external/ds4's pinned SHA
# changes, golden fixtures MUST be recaptured against the freshly rebuilt
# binary before the bump lands. A rebase can apply cleanly and still be
# semantically wrong (the patch set instruments ds4_agent.c's decode loops and
# emitters). See BRIEF.md "The fork" and external/ds4/docs/fork-ledger.md.
engine:
    git submodule update --init external/ds4
    make -C external/ds4 ds4-agent

# Live capture against the real engine. Never part of CI; takes minutes.
# Landed 2026-08-26 (P21).
capture:
    swift run swiftstar-drive

# Assemble .build/SwiftStar.app (release build + Info.plist + icon)
app:
    Tools/make-app.sh
