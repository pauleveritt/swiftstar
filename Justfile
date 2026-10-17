# Enforce docs/sdd.md's caps: ROADMAP cycle rows (Direction <= 300,
# Status <= 400 characters) and plans under docs/superpowers/plans/ (under
# 400 lines). Cells split on pipes outside backtick code spans, so a `a|b`
# span doesn't shift the columns.
lint-docs:
    #!/usr/bin/env bash
    set -euo pipefail
    fail=0
    awk '
        /^\| [A-Z]+\.?[0-9]/ {
            n = split($0, chars, "")
            depth = 0; cell = 0; buf = ""
            delete cells
            for (i = 1; i <= n; i++) {
                c = chars[i]
                if (c == "`") { depth = 1 - depth; buf = buf c; continue }
                if (c == "|" && depth == 0) { cells[cell] = buf; cell++; buf = ""; continue }
                buf = buf c
            }
            d = cells[3]; s = cells[4]
            if (length(d) > 300) {
                printf "ROADMAP.md: Direction cell is %d chars (cap 300): %s...\n", length(d), substr(d, 1, 70)
                bad = 1
            }
            if (length(s) > 400) {
                printf "ROADMAP.md: Status cell is %d chars (cap 400): %s...\n", length(s), substr(s, 1, 70)
                bad = 1
            }
        }
        END { exit bad }
    ' ROADMAP.md || fail=1
    for f in docs/superpowers/plans/*.md; do
        lines="$(wc -l < "$f" | tr -d ' ')"
        if [ "$lines" -ge 400 ]; then
            echo "$f: $lines lines (must be under 400; split the cycle)"
            fail=1
        fi
    done
    exit $fail

# Point git at the tracked .githooks/ dir so pre-commit runs `lint-docs`.
# Once per clone; `git config` writes to this repo's untracked .git/config.
install-hooks:
    git config core.hooksPath .githooks
    @echo "pre-commit will now run 'just lint-docs' on every commit."

# ds4-engine's report on the newest session of this repository (AN.4):
# time, rates, prompts, syncs and proposals. A session id or directory
# first picks one; `--json` gives the contract, `--turn N` one prompt.
last *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    args=({{ARGS}})
    if [[ ${#args[@]} -eq 0 || ${args[0]} == -* ]]; then
        newest=$(ds4-dogfood sessions --json --source "$PWD" --limit 1 \
            | python3 -I -c 'import json, sys; s = json.load(sys.stdin); print(s[0]["path"] if s else "")')
        [[ -n $newest ]] || { echo "last: no session found for $PWD" >&2; exit 1; }
        args=("$newest" ${args[@]+"${args[@]}"})
    fi
    exec ds4-dogfood report "${args[@]}"

# The fixture recorder's tests. -B keeps __pycache__ out of the tree.
test-tools:
    python3 -I -B -m unittest discover -s Tools/tests

# Test runs are capped at TEST_SECS (the build before them is not), so a
# test that never ends fails fast instead of hanging the shell.
TEST_SECS := env("SWIFTSTAR_TEST_SECS", "180")

# Fast tier: SwiftStarKit against fixtures. No model, no network, no
# subprocess; the grep below refuses them in Tests/SwiftStarKitTests.
test: test-tools
    ! grep -rn 'Process(\|URLSession\|NWConnection\|posix_spawn\|Darwin\.\|socket(' Tests/SwiftStarKitTests
    swift build --build-tests
    Tools/with-timeout.sh {{TEST_SECS}} swift test --skip-build

# Integration tier: real processes and files against the fake ds4-dogfood
# (fixtures/engine/fake-ds4-dogfood), which replays committed fixtures. Same
# suite, with the SWIFTSTAR_INTEGRATION-gated tests enabled.
integration:
    swift build --build-tests
    SWIFTSTAR_INTEGRATION=1 Tools/with-timeout.sh {{TEST_SECS}} swift test --skip-build

# One suite or test, both tiers' tests enabled, capped at 60s: the inner
# loop's check. `just focus ProjectRootTests`.
focus FILTER:
    swift build --build-tests
    SWIFTSTAR_INTEGRATION=1 Tools/with-timeout.sh 60 swift test --skip-build --filter '{{FILTER}}'

# Live tier: record one engine fixture (tool-read, stop, error,
# relaunch-rewind or tool-rejected) from the real `ds4-dogfood tui --ndjson`
# into fixtures/engine/. Needs ds4-engine and real weights for MODEL. See
# fixtures/engine/provenance.md for the re-record rule and what each
# fixture must contain.
capture SCENARIO SEED="7" MODEL="qwen3.8-27b":
    Tools/record-engine-fixture.py "${DS4_DOGFOOD:-ds4-dogfood}" "$PWD" {{SCENARIO}} fixtures/engine/{{SCENARIO}}.ndjson {{SEED}} {{MODEL}}

# Assemble .build/SwiftStar.app (release build + Info.plist + icon)
app:
    Tools/make-app.sh
