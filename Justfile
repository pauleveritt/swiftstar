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

# Live capture against the real engine. Never part of CI; takes minutes.
# Arrives in P5.
capture:
    swift run swiftstar-drive
