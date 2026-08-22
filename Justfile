# Docs. The CI build is the strict `-W` one-shot; these are for working locally.

# Rebuild the docs as you edit them, serving on http://127.0.0.1:8000
watch-docs:
    uv run --group docs sphinx-autobuild docs docs/_build/html

# One-shot strict build -- the same gate CI runs
docs:
    uv run --group docs sphinx-build -W -b html docs docs/_build/html

# Fast tier: no model, no network, no subprocess. Arrives in P2.
test:
    swift test

# Build ds4-server and ds4-agent from the pinned submodule SHA (P1).
#
# STANDING RULE — recapture on every bump: whenever external/ds4's pinned SHA
# changes, golden fixtures MUST be recaptured against the freshly rebuilt
# binary before the bump lands. A rebase can apply cleanly and still be
# semantically wrong (the patch set instruments ds4_agent.c's decode loops and
# emitters). See BRIEF.md "The fork" and external/ds4/docs/fork-ledger.md.
engine:
    git submodule update --init external/ds4
    make -C external/ds4 ds4-server ds4-agent

# Live capture against the real engine. Never part of CI; takes minutes.
# Arrives in P5.
capture:
    swift run swiftstar-drive
