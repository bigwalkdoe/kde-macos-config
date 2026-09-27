# kde-macos-config

A clean, reversible, reproducible KDE Plasma configuration that gives Fedora KDE
a polished **macOS-inspired** workflow while staying 100% native to KDE Plasma.

> Design goal: **minimal + premium + restrained + native + fast.**
> Not: theme-heavy + gimmicky + fragile.
> macOS interaction model + KDE/Linux functionality. KDE stability always wins
> over visual similarity.

```
┌──────────────────────────────────────────────────────────────┐
│  app menu      ▍▍▍         WiFi 🔊 🔋 19:32  │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│                        CLEAN DESKTOP                         │
│                                                              │
│                  ╭──────────────────────────╮                │
│                  │ 🍎 ● ● ● ● ● ● ● ● 🗑 │                │
│                  ╰──────────────────────────╯                │
└──────────────────────────────────────────────────────────────┘
```

---

## 1. What this project does

| Area | Target |
|---|---|
| Top menu bar | `gridUnit × 10/6` (30 px at the default gridUnit 18), full-width, flush: global menu (left) · workspace pager (center) · system tray + clock (right) |
| Dock | floating, centered, icon-only, `gridUnit × 26/9` (52 px at gridUnit 18), fit-to-content: Launcher · Dolphin · Konsole · Firefox · Chrome · VSCode · divider · Trash |
| Desktop | clean "Desktop" containment — **no icons**, no folder clutter, wallpaper only |
| Windows | Orchis aurorae decoration; borderless maximized windows; curated KWin effects (blur in, wobbly/cube/lamp out) |
| Workspaces | 4 virtual desktops (1 row) with standard KDE shortcuts kept intact |
| Launcher | `Meta` → Kickoff (unchanged default), `Alt+F2` → KRunner, `Meta+W` → Overview |
| Theme system | Orchis look-and-feel + Orchis colors + FairyWren_Light icons + Bibata-Modern-Ice cursor + Noto Sans, with a `--dark` variant |
| GTK apps | Breeze (light) / Orchis-Dark (dark) via user-level `gtk-3.0/gtk-4.0/settings.ini` |

## 2. Design principles followed

- **One targeted text edit, no bulk regex.** Panel layout is generated with the
  **native Plasma scripting API** (`PlasmaShell.evaluateScript`) — the same
  API Plasma's own "New Panel" templates use. The single exception is the
  desktop containment switch (`plugin=org.kde.plasma.folder` →
  `org.kde.desktopcontainment`), which is not reachable from that API.
  `apply.sh` converts **only** folder views that own no `[Applets]` section
  (an empty folder view = the plain desktop). A folder view that *does* have
  desktop icons is left untouched and reported by containment id, so a
  deliberate Folder View on a second screen is never silently destroyed.
- **No assumed IDs.** The layout script enumerates live panels via `panelIds()`
  and rebuilds them; the desktop containment switch (`Folder View` → `Desktop`)
  uses the exact value System Settings writes (`org.kde.desktopcontainment`).
- **No random third-party themes.** Everything here comes from packages already
  installed on this machine (Orchis / FairyWren / MkosBigSur assets) or stock KDE
  components. **No Latte Dock, no abandoned infrastructure.** The one asset not
  shipped by an installed package — the wavy-lines wallpaper — is vendored in
  `assets/wallpapers/` and auto-installed by `apply.sh` if the live copy is
  missing, so a clean machine never fails on it. The splash theme is opt-in:
  `apply.sh` only writes `ksplashrc` when the theme it names is actually
  installed, so it never points at a missing splash.
- **Native over third-party.** Global menu = `org.kde.plasma.appmenu`, dock =
  `org.kde.plasma.icontasks` (the Plasma 6 Icons-only Task Manager), tray =
  `org.kde.plasma.systemtray`.
- **Backup before touch, always.** Every apply creates a timestamped backup
  under `~/.config/kde-backups/` and restores it automatically on failure.
- **User-level only.** No system files are touched by `apply.sh`.
  **One deliberate exception:** the login screen (SDDM) requires root, so it is
  handled as an explicit, separate step — `sudo ./scripts/install-sddm-orchis.sh`.

## 3. Repository layout

```
kde-macos-config/
├── README.md            this file
├── backup.sh            timestamped backup -> ~/.config/kde-backups/ (+ retention)
├── apply.sh             [--light|--dark] preflight -> backup -> apply -> verify
├── switch.sh            automatic dark/light switching (systemd user timer)
├── sync.sh              snapshot live config -> config/ (normalized, git-ready)
├── rollback.sh          restore the most recent backup
├── scripts/restore-backup.sh   the single restore implementation (shared)
├── detect.sh            non-destructive environment inventory
├── verify.sh            PASS/FAIL verification (files + live session + health)
├── assets/wallpapers/   vendored 5K wallpaper (generated; applied by apply.sh if missing or stale)
├── config/              diagnostic snapshots of the live config (see below)
├── .github/workflows/   CI: shellcheck + bash -n on every push/PR
├── scripts/
│   ├── patch-lnf.sh     pins icons/cursor/decoration into user-local Orchis LNF
│   ├── install-sddm-orchis.sh  (sudo) installs the Orchis login theme
│   ├── restore-backup.sh       shared restore path used by rollback.sh + fail-safe
│   ├── layout.js        panel layout (top bar + dock), native scripting API
│   ├── dock-launchers.list     pinned dock apps, edited to add/remove one
│   ├── resolve-launchers.sh    keeps only launchers that are installed
│   ├── desktop-file-path.sh    resolves a desktop-file id to its path
│   ├── make-wallpaper.py       regenerates the vendored wallpaper (needs numpy+Pillow)
│   ├── tray-config.js   system tray curation (pinned items + order)
│   └── probe-panels.js  read-only panel/widget probe (detect.sh + verify.sh)
└── screenshots/         captured after apply
```

`config/` is a **diagnostic record, not input**: nothing in this repo reads it
(`apply.sh` drives everything through `kwriteconfig6` and the Plasma scripting
API). It exists so a config diff is reviewable in git. `sync.sh` normalizes away
per-screen UUIDs, per-desktop `[Tiling][…]` sections, regenerated desktop IDs and
the `[Updates]` migration log, so re-syncing does not churn the diff. Plasma also
generates the numeric `[Containments][N]`/`[Applets][N]` indices, which differ
per machine and are *not* normalized.

## 4. Quick start

```bash
cd ~/kde-macos-config
./detect.sh          # inventory (read-only)
./apply.sh           # apply the light look
./apply.sh --dark    # apply the dark look
./verify.sh          # status report
./sync.sh            # snapshot current live config -> config/ (normalized)
./sync.sh --commit   # ...and commit it
./rollback.sh        # restore the most recent backup
./switch.sh --install       # set up automatic dark/light switching
./switch.sh --check         # print desired vs current mode
./switch.sh --auto          # switch mode if the clock crossed a boundary

# Dark/light switching is safe in any of these forms:
#   ./apply.sh --light | --dark   (run this repo; preferred)
#   System Settings -> Global Theme -> Orchis / Orchis-dark
#   lookandfeeltool -a com.github.vinceliuice.Orchis[-dark]
# All three paths converge because scripts/patch-lnf.sh normalizes the
# user-local LNF defaults before each apply — icons and cursor stay pinned.
```

## 5. What exactly is applied

### Theme (light default / `--dark` variant)
- **Look-and-feel:** `com.github.vinceliuice.Orchis` (`Orchis-dark`) applied as a full
  Global Theme via `plasma-apply-lookandfeel -a` (records `kdeglobals [KDE]
  LookAndFeelPackage` and applies the patched defaults: colorscheme, icons,
  cursor, KWin aurorae decoration, kvantum widgets). `plasma-apply-desktoptheme`
  is also run for the plasma style. The packaged panel layout is NOT used; see
  Panels below.
  The stock Orchis LNF defaults reference uninstalled Vimix cursors + Tela-circle
  icons, so `scripts/patch-lnf.sh` patches the user-local LNF copies to keep the
  repo's FairyWren icons + Bibata cursors on **every** switch path. It also
  normalizes the window-decoration plugin id: the packaged defaults declare
  `org.kde.kwin.aurorae` while the live session runs `org.kde.kwin.aurorae.v2`
  (see *KWin* below for why both are loadable).
  KDE 6.7's built-in auto dark/light Global Theme switcher is disabled on each
  apply (`AutomaticLookAndFeel=false`, `AutomaticLookAndFeelOnIdle=false`) and
  its `DefaultLight/DarkLookAndFeel` keys are pinned to the Orchis pair so
  nothing but this switch path can flip themes.
- **Color scheme:** `Orchis` / `OrchisDark` (installed) via `plasma-apply-colorscheme`.
- **Icons:** `FairyWren_Light` / `FairyWren_Dark` (installed; the macOS-style icon
  set that belongs to the Orchis ecosystem). The Orchis LNF would fall back to
  missing `Tela-circle` icons, so the icon theme is explicitly overridden.
- **Cursor:** `Bibata-Modern-Ice` (macOS smoothed edges; replaces the sharp Breeze cursor the LNF ships)
- **Fonts:** keep `Noto Sans 10` (clean Helvetica-like family, readable at 10pt).
- **Splash:** `AppleSplash`, written **only if it is actually installed** (it is
  here, as a `plasma/look-and-feel` package providing `contents/splash/Splash.qml`
  — see `scripts/splash-theme-path.sh`). Override with `SPLASH=<name> ./apply.sh`.
  It does **not** survive switching the look-and-feel outside this repo: Plasma
  rewrites `ksplashrc` from the LNF every time a theme is applied, so switching in
  System Settings (or `lookandfeeltool`) puts the LNF's own splash back and
  leaves `~/.config/ksplashrc` empty. Re-run `./apply.sh` to re-assert it. This
  only affects the login splash.
- **GTK:** `Breeze` (light) / `Orchis-Dark` (dark) themes, matching `FairyWren`
  icons + Bibata cursors — user-level only.

### Panels (top bar + dock) — `scripts/layout.js`
Executed through `org.kde.PlasmaShell.evaluateScript` (native API):
1. removes **all** existing panels (idempotent; layout fully owned by this file),
2. creates the **top menu bar** (`org.kde.plasma.appmenu` global menu,
   `org.kde.plasma.pager`, `org.kde.plasma.systemtray`, `org.kde.plasma.digitalclock`;
   `gridUnit × 10/6` tall, flush, full width),
3. creates the **dock** (`org.kde.plasma.kickoff`, `org.kde.plasma.icontasks`
   with pinned launchers, `org.kde.plasma.marginsseparator`, `org.kde.plasma.trash`;
   `gridUnit × 26/9` tall, floating, centered, fit-to-content).

Panel heights scale with your `gridUnit`; `verify.sh` therefore range-checks them
(24–44 px and 44–66 px) rather than comparing exact values.

#### Pinned dock launchers — `scripts/dock-launchers.list`

The launcher list is **not** hardcoded in `layout.js`. It lives in
`scripts/dock-launchers.list`, one app per line in dock order:

```
org.kde.dolphin.desktop
org.kde.konsole.desktop
org.mozilla.firefox.desktop
com.google.Chrome.desktop
com.microsoft.VSCode.desktop|code.desktop
```

`apply.sh` resolves that list through `scripts/resolve-launchers.sh`, which keeps
only ids whose `.desktop` file is actually installed here
(`scripts/desktop-file-path.sh`), then injects the result into `layout.js`. Ids
that are not installed are skipped and reported, never pinned. Alternatives
(`a.desktop|b.desktop`) let one line cover distros that disagree on the id; the
first one installed wins, so an app is pinned at most once.

This matters because a pinned `applications:<id>` with no desktop file is drawn by
Plasma as a generic **"Unknown application"** tile, and since `layout.js` rewrites
the entire launcher list on every apply, **unpinning it by hand does not stick**.
This repo shipped `applications:code.desktop` while VS Code installs
`com.microsoft.VSCode.desktop`, which is how a permanently unremovable broken tile
ended up in the dock. `verify.sh` now checks every live launcher against the same
resolver, so a stale id fails verification instead of reaching your screen.

**To remove an app from the dock:** delete its line from
`scripts/dock-launchers.list` and re-run `./apply.sh`. Unpinning in the Plasma UI
alone will be reverted by the next apply.

`layout.js` is a template: it contains an `@DOCK_LAUNCHERS@` token that `apply.sh`
substitutes. Running it directly leaves the launchers untouched and says so in the
log, rather than pinning an unverified id.

`scripts/tray-config.js` then curates the tray so the bar shows only:
clipboard · network · bluetooth · volume · brightness · battery · notifications
(everything else stays available in the tray's overflow menu).

### Desktop
`plugin=org.kde.plasma.folder` → `org.kde.desktopcontainment` (the exact value
System Settings writes for the icon-less "Desktop"), i.e. wallpaper + widgets,
**no desktop icons**. Wallpaper: `wavy_lines_v02_5120x2880.png` — a 5K
waves image that also covers dual monitors. It is generated by
`scripts/make-wallpaper.py` (not a third-party asset, so it is MIT-covered and
reproducible), vendored in `assets/wallpapers/`; `apply.sh` installs it when the
live copy is missing **or differs from the vendored asset**, so a clean machine
never fails on it and a stale same-named file — an earlier release, or an image
unpacked from the original Downloads zip — cannot be applied by mistake.
`verify.sh` checks the bytes match, not just that a file of that name exists.

### KWin
- `library=org.kde.kwin.aurorae.v2` + `theme=__aurorae__svg__Orchis`
  (`...Orchis-dark` in dark mode). Aurorae installs **two** decoration plugins
  side by side — `org.kde.kwin.aurorae.so` and `org.kde.kwin.aurorae.v2.so` in
  `/usr/lib64/qt6/plugins/org.kde.kdecoration3/`, each registering its own id —
  and **both load**. So this is not "v1 is broken": it is that the live session
  runs the `.v2` id while the packaged Orchis LNF defaults still declare the v1
  id, so applying the LNF from System Settings would silently switch plugins.
  `apply.sh` writes `.v2` and `scripts/patch-lnf.sh` rewrites the LNF defaults
  to match, closing that path.
- `BorderlessMaximizedWindows=true` (macOS-style maximized windows)
- 4 desktops, 1 row; **existing desktop UUIDs are preserved** and only
  genuinely missing/empty/duplicate slots get a fresh one. Desktop-scoped KWin
  rules (per-desktop wallpaper, noanimation, keep-above) are keyed on these
  UUIDs, so an earlier version that regenerated `Id_2..Id_4` on every apply
  orphaned all of them and churned the config 2×/day via `switch.sh --auto`
- Effects: blur/fade/glide/scale/resize/maximize/minimize/overview on;
  wobbly windows, magic lamp, ball, cube off (GPU-heavy/legacy)
- `org.kde.KWin.reconfigure` is called so settings apply without a restart

### Multi-monitor behaviour
- Nothing is hard-coded to a screen: panels are placed on the default (primary)
  screen at apply time; Plasma panels never duplicate themselves across displays.
- Display resolution/refresh/rotation/orientation/scale are **never touched**
  (`kwinoutputconfig.json` is only backed up, never modified).
- `kscreen-doctor -o` output is recorded in the applied-state report.
- The existing user kwin rule "YouTube Dual Monitor Wall" is preserved untouched.

## 6. Keyboard map (all KDE defaults, kept intact)

| Action | Shortcut |
|---|---|
| Application launcher | `Meta` (or `Alt+F1`) |
| KRunner | `Alt+F2` |
| Overview | `Meta+W` |
| Grid view | `Meta+G` |
| Show desktop | `Meta+D` (peek) / `Ctrl+F12` |
| Next/prev desktop | `Meta+Ctrl+Right/Left` |
| Move window to desktop | `Shift+Meta+Ctrl+Right/Left` |
| Tiles editor | `Meta+T`; drag-to-edge tiling on |

## 7. Fullscreen behaviour

Both panels use **Dodge windows**: `[PlasmaViews][Panel N] panelVisibility=2`.
The bar and dock stay hidden until the mouse reaches the screen edge, and
fullscreen surfaces dodge them — macOS-style.

The enum is Plasma's own (`0`=NormalPanel, `1`=AutoHide, `2`=DodgeWindows,
`3`=WindowsGoBelow). It cannot be set from the panel scripting API, so
`apply.sh` writes the key after `scripts/layout.js` has created the panels, and
`verify.sh` asserts it reads back as `2`. Because Plasma owns and re-serialises
`panelVisibility`, the value survives the shell restarts at the end of an apply.

> This was previously broken: the key was written as `hiding`, which does not
> exist in Plasma 6.x, so Plasma silently dropped it on the next
> `plasmashellrc` write and the panels stayed always-visible.

Still worth checking interactively after an apply: Firefox `F11`, Chrome `F11`,
maximized windows, and video fullscreen.

## 8. Rollback & safety

- Every apply creates `~/.config/kde-backups/<timestamp>/` with all touched
  files. `apply.sh` verifies the backup before changing anything and prints its
  path.
- If any step fails, `apply.sh` restores that backup and restarts plasmashell
  automatically (fail-safe).
- `./rollback.sh` restores the **most recent** backup — no manual bookkeeping.
- Re-applying is safe: the layout script is idempotent.
- Backups also snapshot the pristine user-local Orchis LNF defaults (the files
  `scripts/patch-lnf.sh` rewrites), `~/.config/fontconfig/fonts.conf` (which
  `apply.sh` overwrites), and whether the vendored wallpaper was already present,
  so the restore is the exact inverse of the apply.
- **One restore implementation.** `scripts/restore-backup.sh` holds the list of
  restored files; both `rollback.sh` and `apply.sh`'s fail-safe call it, so the
  two cannot drift. Adding a write to `apply.sh` means adding it to `backup.sh`'s
  `FILES` *and* to that list — otherwise the change is silently irreversible.
- **Retention:** the newest 20 timestamped backups are kept
  (`KDE_BACKUP_KEEP=50 ./apply.sh` to change). Only `YYYYMMDD-HHMMSS`
  directories are ever pruned, so anything you put in that directory by hand is
  safe.
- **Concurrency:** `apply.sh` holds `.apply.lock` (`flock`) for its whole run, so
  the `switch.sh` timer landing on top of a manual apply exits instead of two
  runs rewriting `kwinrc`/`plasmashellrc` and restarting plasmashell at once.
- **Preflight:** the theme assets (Orchis LNF, color scheme, FairyWren icons,
  Bibata cursor) are checked *before* anything is written, so a machine missing
  one fails immediately with a list of what to install rather than partway
  through the apply.

## 9. Automatic dark/light switching (`./switch.sh`)

`switch.sh` flips the theme on a daily schedule using a systemd **user** timer —
no cron, no root:

- `./switch.sh --install`  — creates `kde-macos-switch.{service,timer}` under
  `~/.config/systemd/user/` and enables it. The timer fires 2 min after login,
  then every 15 min; the service runs `switch.sh --auto`, which only applies when
  the clock has actually crossed a boundary (so it is a no-op otherwise).
- `./switch.sh --check` — prints desired vs current mode without changing anything.
- `./switch.sh --auto` — applies dark/light if it differs from the current mode.
  It defers (and retries on the next 15 min tick) while the session is **locked**,
  since restarting plasmashell on an unattended screen is disruptive.
- Times default to sunrise/sunset (`06:30` / `19:30`). Override per machine in
  `~/.config/kde-macos/switch.conf`:
  `SUNRISE=07:00` / `SUNSET=20:00`. The file is sourced, so it is validated on
  every run: values must be `HH:MM` and sunrise must precede sunset, otherwise
  the script exits with a clear error instead of silently failing forever.
- `./switch.sh --light|--dark` — explicit manual switch (same as `apply.sh`).
- `./switch.sh --uninstall` — disables the timer and removes the unit files.
- Timer-driven decisions are appended to `~/.config/kde-macos/switch.log`, so a
  switch that happened while you were away is still auditable.

Note: the schedule drives `apply.sh`, which already guarantees icons/cursor stay
pinned (see scripts/patch-lnf.sh), so both automatic and manual switching behave
identically.

## 10. Known limitations

- **Login screen (SDDM):** not customized by `apply.sh` — it requires root
  (`/usr/share/sddm/themes`, `/etc/sddm.conf.d/`). Install the Orchis login
  theme explicitly (one-time, idempotent, preserves your cursor/font settings):
  `sudo ./scripts/install-sddm-orchis.sh`. The installer exits immediately if
  the theme is already present and configured; pass `--force` to re-clone and
  reinstall anyway. Preview without logging out:
  `sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/Orchis &`.
- **Reboot persistence:** verify.sh records the boot ID when apply.sh succeeds
  (`.applied-light`/`.applied-dark`). On a later run it reports **PASS** if the
  system has since rebooted (settings survived a full reboot), or an INFO hint
  when verification happens in the same boot — a full `reboot` check is still a
  manual step the first time, then automated from then on.
- **Modelink:** it is a development project (`~/dev/github/modelink-*`), not an
  installed application, so no dock entry is created. To pin it: add a
  `~/.local/share/applications/modelink.desktop` and add its id to
  `scripts/dock-launchers.list`.
- **GTK light theme:** installed Orchis GTK themes are dark-only, so light mode
  maps GTK apps to native `Breeze`. Firefox/Chrome/VSCode draw their own UI.
- **fs-verity digest mismatches in the kernel log.** btrfs implements fs-verity
  per file, and this session's kernel log carries a burst of
  `fs-verity (dm-0, inode N): FILE CORRUPTED!` lines. They are *not* evidence of
  a failing disk: over the same 24h window the NVMe and btrfs logged zero I/O,
  checksum or medium errors, the affected inodes no longer resolve to any live
  file, and the majority of reads return exactly one 4 KiB block of zeros
  (`real_hash` = sha256 of 4096 zero bytes) — the signature of btrfs handing back
  an unwritten extent or a stale page-cache page rather than damaged media. A
  minority return non-repeating data, which is the part that would look like a
  real read fault. `verify.sh` counts the two separately and only warns on the
  second. The burst tracks heavy-I/O phases rather than idling: no event
  arrives while the machine is quiet, and re-reading live verity-protected
  system libraries produces none either.
  To settle it for real, run `./scripts/check-storage.sh`. It scrubs every
  btrfs mount — the only step that actually re-reads and re-checksums the
  data — then reads the device error counters, maps the affected inodes to
  live files, and exits non-zero if it finds a genuine fault. `--dry-run`
  reports the same information without scrubbing, and says plainly that it
  cannot conclude anything about the data. Add a `memtest86+` boot to rule
  out RAM; no disk check covers that.
  **Settled on this machine (2026-09-27):** the checker scrubbed 140.74 GiB on
  `/` and 140.10 GiB on `/home` — `Error summary: no errors found` on both —
  with every device counter at 0 and no mismatch resolving to a live file. All
  allocated data was re-read and re-checksummed clean, so the mismatches are
  confirmed to be a read-path artifact rather than damaged media. The one
  variable no disk check covers is RAM, so `memtest86+` still needs one boot to
  close that. `verify.sh` keeps warning about the mismatches regardless: it
  reports what the kernel logged, and the log does not change because a scrub
  passed.
- **No fullscreen detection for auto-switching.** `switch.sh --auto` skips a
  switch while the session is locked, but it cannot tell whether you are in a
  fullscreen window or a presentation — KWin's `queryWindowInfo` D-Bus call is
  interactive (it asks you to click a window) and is not usable from a timer. A
  switch while you are presenting will restart plasmashell. Use
  `./switch.sh --light|--dark` manually if that matters to you.
- **Containment ids are not normalized in `config/`.** `sync.sh` strips UUIDs and
  migration logs, but Plasma's numeric `[Containments][N]`/`[Applets][N]`
  indices are machine-generated, so a snapshot diff between two machines still
  shows them renumbered. `verify.sh`, not the snapshots, is the real check.
- **No automated functional tests.** CI runs `shellcheck` + `bash -n` only;
  `verify.sh` needs a live Plasma session and cannot run in CI.

## 11. Verification checklist (`./verify.sh`)

Desktop (clean containment, wallpaper, vendored asset present) · top bar and
dock (global menu, tray, clock, pager, launcher, trash, floating,
fit-to-content) · exactly two panels · **panel visibility = dodge windows** ·
kwin (aurorae.v2 decoration, 4 desktops, blur on, wobbly off) · theme (LNF,
colors, icons, cursor, cursor size, font, splash resolution) · LNF defaults
pinned for cursor, icons and decoration id · the pinned
`DefaultLight/DarkLookAndFeel` pair · **GTK 3 *and* 4** wiring ·
fontconfig rejectfont · backup present. SDDM login theme reports PASS when
installed (`verify.sh` SKIPs it otherwise — it is an optional,
separately-installed step). Reboot persistence auto-detects whether the running
settings survived a reboot since the last apply, reading the marker for the mode
that is actually applied.

Manual checks after apply: global menu shows app menus (File/Edit/View…),
tray icon actions work, clock updates, pinned dock apps launch, running apps
show indicators, trash works, fullscreen dodges the panels cleanly, dual
monitor panels stay on the primary screen.

## 12. License

MIT — see [LICENSE](LICENSE). Scripts, JavaScript, docs **and** the vendored
wallpaper are covered by it. The wallpaper is not a third-party asset: it is
generated by `scripts/make-wallpaper.py` from constants in that file, so its
provenance is checkable rather than claimed — `./scripts/make-wallpaper.py
--check` confirms the committed PNG still matches the generator. (It replaced an
earlier `wavy_lines_v01` image that was committed with no provenance at all,
which is why the generator exists.) Orchis, FairyWren, Bibata and the SDDM theme
are not bundled — they come from upstream packages (Orchis is GPL-3.0).
