# screenshots/

Reference captures. **No script reads any of this** — it is documentation only.

| File | What it is |
|---|---|
| `desktop-dual-20260924.png` | Current state after `./apply.sh`, dual monitor. The canonical "what this looks like" capture. |
| `desktop-after-apply.png` | Single-screen capture from the initial apply. |
| `baseline-check.png` | Before/after baseline used while first validating `apply.sh`. |

The panel layout that actually gets applied is `../scripts/layout.js`, written
through `PlasmaShell.evaluateScript`.

Removed in cleanup: the `fs-test-*.png` / `fullscreen-test.png` scratch captures
from debugging fullscreen behaviour, and a stray `layout-applied.js` that was a
`layout-templates`-format *export* of the applied layout — an output artifact
that embedded machine-specific values (absolute wallpaper path, screen
geometry) and was never an input to `apply.sh`.
