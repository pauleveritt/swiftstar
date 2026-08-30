#!/bin/sh
# P24.1 measurement protocol. Run from the repo root.
#
#   Tools/p24-1-measurement/run.sh          # treatment (windowed reads, as shipped)
#   Tools/p24-1-measurement/run.sh control  # control arm -- see control.patch first
#
# The control arm requires applying control.patch (which reverts
# HostToolExecutor.readResult to its pre-P24.1 body) and rebuilding. Do that on
# a throwaway branch and discard it; the patch is committed so the arm is
# auditable and re-runnable, which the original run was not.
set -eu
: "${SWIFTSTAR_MODEL:?set SWIFTSTAR_MODEL to the gguf path}"
WS="${P241_WORKSPACE:-$(mktemp -d)/p241-ws}"
mkdir -p "$WS/Sources/SwiftStar" "$WS/Sources/SwiftStarKit"
cp Sources/SwiftStar/AgentView.swift Sources/SwiftStar/AgentController.swift "$WS/Sources/SwiftStar/"
cp Sources/SwiftStarKit/ReadWindow.swift Sources/SwiftStarKit/ToolResultCondenser.swift "$WS/Sources/SwiftStarKit/"
cp ROADMAP.md BRIEF.md "$WS/"
echo "workspace: $WS"

# CAPTURE_TURN_TIMEOUT is deliberately 240, not the tool's 900 default: the
# control arm is expected to fail to converge, and 900 x 12 prompts is an hour
# of wall clock to learn that. "Timed out" in the write-up means "did not finish
# in 240s", never "cannot finish".
CAPTURE_GGUF="$SWIFTSTAR_MODEL" \
CAPTURE_CTX=32768 \
CAPTURE_TURN_TIMEOUT=240 \
CAPTURE_MODEL_LOAD_TIMEOUT=600 \
CAPTURE_HOST_TOOLS=1 \
CAPTURE_WORKSPACE="$WS" \
CAPTURE_PROMPTS_FILE=Tools/p24-1-measurement/prompts.txt \
swift run swiftstar-drive

echo
echo "Analyse the newest capture with BOTH:"
echo "  swift run swiftstar-analyze rereads <capture-dir-name>"
echo "  python3 Tools/window-spread.py captures/<capture-dir-name>"
