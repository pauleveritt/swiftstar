project = "SwiftStar"
author = "Paul Everitt"
copyright = "2026, Paul Everitt"

extensions = ["myst_parser"]
myst_enable_extensions = ["colon_fence", "deflist", "linkify"]

html_theme = "furo"
html_title = "SwiftStar"

exclude_patterns = ["_build"]

# The superpowers trail is the design record: specs, plans, and research kept
# as they were written, including withdrawn framings. Sphinx must not try to
# render it as part of the site, and nothing should edit it to satisfy a build.
exclude_patterns += ["superpowers/*"]
