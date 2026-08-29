# Docs. The CI build is the strict `-W` one-shot; these are for working locally.

# Rebuild the docs as you edit them, serving on http://127.0.0.1:8000
watch-docs:
    uv run --group docs sphinx-autobuild docs docs/_build/html

# One-shot strict build -- the same gate CI runs
docs:
    uv run --group docs sphinx-build -W -b html docs docs/_build/html

# Enforce docs/sdd.md's size caps: ROADMAP phase-table Direction/Status
# cells, plan docs under 400 lines / 25% fenced code. Written convention
# alone has already failed silently once (see docs/sdd.md, "The phase
# table"). Direction/Status caps (900/1000 chars) are calibrated against
# this project's own post-cleanup ROADMAP, not picked in the abstract --
# the first version of this gate used 300 chars, which was aspirational and
# unverified: even the row cited as the exemplar of "already short" (P20)
# failed it by 7x. Caught only because a docs-restructuring pass ran the
# actual gate instead of trusting the number in docs/sdd.md.
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
        read -r lines pct <<< "$(awk '
            { n++ }
            /^```/ { infence = !infence; next }
            infence { c++ }
            END { pct = (n > 0) ? int(c * 100 / n) : 0; print n, pct }
        ' "$f")"
        if [ "$lines" -gt 400 ] || [ "$pct" -gt 25 ]; then
            echo "$f: $lines lines, ${pct}% fenced (cap 400 lines / 25% fenced)"
            fail=1
        fi
    done
    exit $fail

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
