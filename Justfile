# Docs. The CI build is the strict `-W` one-shot; these are for working locally.

# Rebuild the docs as you edit them, serving on http://127.0.0.1:8000
watch-docs:
    uv run --group docs sphinx-autobuild docs docs/_build/html

# One-shot strict build -- the same gate CI runs
docs:
    uv run --group docs sphinx-build -W -b html docs docs/_build/html

# Enforce docs/sdd.md's size caps: ROADMAP phase-table cells under 300 chars,
# plan docs under 400 lines / 25% fenced code. Written convention alone has
# already failed silently once (see docs/sdd.md, "The phase table").
lint-docs:
    #!/usr/bin/env bash
    set -euo pipefail
    fail=0
    while IFS= read -r line; do
        [[ "$line" =~ ^\|\ P[0-9] ]] || continue
        IFS='|' read -ra cells <<< "$line"
        for cell in "${cells[@]}"; do
            len=${#cell}
            if [ "$len" -gt 300 ]; then
                echo "ROADMAP.md: phase-table cell is $len chars (cap 300): ${cell:0:70}..."
                fail=1
            fi
        done
    done < ROADMAP.md
    for f in docs/superpowers/plans/*.md; do
        lines=$(wc -l < "$f")
        fenced=$(awk '/^```/{f=!f;next} f{c++} END{print c+0}' "$f")
        pct=$(( lines > 0 ? fenced * 100 / lines : 0 ))
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
