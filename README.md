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
| Top menu bar | 30 px, full-width, flush: global menu (left) · workspace pager (center) · system tray + clock (right) |
| Dock | floating, centered, icon-only, 52 px, fit-to-content: Launcher · Dolphin · Konsole · Firefox · Chrome · VSCode · divider · Trash |
| Desktop | clean "Desktop" containment — **no icons**, no folder clutter, wallpaper only |
| Windows | Orchis aurorae decoration; borderless maximized windows; curated KWin effects (blur in, wobbly/cube/lamp out) |
| Workspaces | 4 virtual desktops (1 row) with standard KDE shortcuts kept intact |
| Launcher | `Meta` → Kickoff (unchanged default), `Alt+F2` → KRunner, `Meta+W` → Overview |
| Theme system | Orchis look-and-feel + Orchis colors + FairyWren_Light icons + Breeze cursor + Noto Sans, with a `--dark` variant |
| GTK apps | Breeze (light) / Orchis-Dark (dark) via user-level `gtk-3.0/gtk-4.0/settings.ini` |

## 2. Design principles followed

- **No blind config editing.** No bulk regex over
  `plasma-org.kde.plasma.desktop-appletsrc`. Panel layout is generated with the
  **native Plasma scripting API** (`PlasmaShell.evaluateScript`) — the same
  API Plasma's own "New Panel" templates use.
- **No assumed IDs.** The layout script enumerates live panels via `panelIds()`
  and rebuilds them; the desktop containment switch (`Folder View` → `Desktop`)
  uses the exact value System Settings writes (`org.kde.desktopcontainment`).
- **No random third-party themes.** Everything here comes from packages already
  installed on this machine (Orchis / FairyWren / MkosBigSur assets, `AppleSplash`)
  or stock KDE components. **No Latte Dock, no abandoned infrastructure.**
- **Native over third-party.** Global menu = `org.kde.plasma.appmenu`, dock =
  `org.kde.plasma.icontasks` (the Plasma 6 Icons-only Task Manager), tray =
  `org.kde.plasma.systemtray`.
- **Backup before touch, always.** Every apply creates a timestamped backup
  under `~/.config/kde-backups/` and restores it automatically on failure.
- **User-level only.** No system files are touched. (The login screen SDDM theme
  is *not* changed because that requires root; see §9.)

## 3. Repository layout

```
kde-macos-config/
├── README.md            this file
├── backup.sh            timestamped backup -> ~/.config/kde-backups/
├── apply.sh             [--light|--dark] preflight -> backup -> apply -> verify
├── rollback.sh          restore most recent backup + reload desktop
├── detect.sh            non-destructive environment inventory
├── verify.sh            PASS/FAIL verification (files + live session)
├── config/              reference values for every setting this project writes
├── scripts/
│   ├── layout.js        panel layout (top bar + dock), native scripting API
│   └── tray-config.js   system tray curation (pinned items + order)
└── screenshots/         captured after apply (if tooling available)
```

## 4. Quick start

```bash
cd ~/kde-macos-config
./detect.sh          # inventory (read-only)
./apply.sh           # apply the light look
./apply.sh --dark    # apply the dark look
./verify.sh          # status report
./rollback.sh        # restore the most recent backup
```

## 5. What exactly is applied

### Theme (light default / `--dark` variant)
- **Look-and-feel:** `com.github.vinceliuice.Orchis` (`Orchis-dark`) via
  `plasma-apply-desktoptheme` — colors, splash, plasma framework theme, kwin
  decoration wiring. The packaged panel layout is NOT used; see Panels below.
- **Color scheme:** `Orchis` / `OrchisDark` (installed) via `plasma-apply-colorscheme`.
- **Icons:** `FairyWren_Light` (installed; the macOS-style icon set that belongs
  to the Orchis ecosystem). The Orchis LNF would fall back to missing
  `Tela-circle` icons, so the icon theme is explicitly overridden.
- **Cursor:** `Breeze_Light` (native; avoids pulling in the missing `Vimix`
  cursor the LNF references).
- **Fonts:** keep `Noto Sans 10` (clean Helvetica-like family, readable at 10pt).
- **Splash:** `AppleSplash` (installed) via `ksplashrc`.
- **GTK:** `Breeze` (light) / `Orchis-Dark` (dark) themes, `FairyWren_Light`
  icons, `Breeze_Light` cursor — user-level only.

### Panels (top bar + dock) — `scripts/layout.js`
Executed through `org.kde.PlasmaShell.evaluateScript` (native API):
1. removes **all** existing panels (idempotent; layout fully owned by this file),
2. creates the **top menu bar** (`org.kde.plasma.appmenu` global menu,
   `org.kde.plasma.pager`, `org.kde.plasma.systemtray`, `org.kde.plasma.digitalclock`;
   30 px, flush, full width),
3. creates the **dock** (`org.kde.plasma.kickoff`, `org.kde.plasma.icontasks`
   with pinned launchers, `org.kde.plasma.marginsseparator`, `org.kde.plasma.trash`;
   52 px, floating, centered, fit-to-content).

`scripts/tray-config.js` then curates the tray so the bar shows only:
clipboard · network · bluetooth · volume · brightness · battery · notifications
(everything else stays available in the tray's overflow menu).

### Desktop
`plugin=org.kde.plasma.folder` → `org.kde.desktopcontainment` (the exact value
System Settings writes for the icon-less "Desktop"), i.e. wallpaper + widgets,
**no desktop icons**. Wallpaper: `wavy_lines_v01_5120x2880.png` (already
installed; a subtle 5K waves image that also covers dual monitors).

### KWin
- `decorationTheme=Orchis` (rounded, minimal title bar)
- `BorderlessMaximizedWindows=true` (macOS-style maximized windows)
- 4 desktops, 1 row; baseline desktop IDs preserved, 2–4 get fresh UUIDs
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

The dock and top bar use `hiding = "normal"` (always visible; windows may cover
them). On Plasma Wayland, fullscreen windows take the whole screen, including
over the panels, without any arbitrary window rules. To be verified interactively
after apply (Firefox `F11`, Chrome `F11`, maximized windows, video fullscreen).

## 8. Rollback & safety

- Every apply creates `~/.config/kde-backups/<timestamp>/` with all touched
  files. `apply.sh` verifies the backup before changing anything and prints its
  path.
- If any step fails, `apply.sh` restores that backup and restarts plasmashell
  automatically (fail-safe).
- `./rollback.sh` restores the **most recent** backup — no manual bookkeeping.
- Re-applying is safe: the layout script is idempotent.

## 9. Known limitations

- **Login screen (SDDM):** not customized — requires root
  (`/etc/sddm.conf.d/`), and this project intentionally never touches system
  files. To use an Orchis SDDM theme later: install it, then with sudo set
  `[Theme] Current=<theme>` in `/etc/sddm.conf.d/10-orchis.conf`.
- **Reboot persistence:** apply.sh verifies persistence across a full
  plasmashell reload (equivalent to a session reload). A full `reboot` check is
  a manual step — run `./verify.sh` after the next login.
- **Modelink:** it is a development project (`~/dev/github/modelink-*`), not an
  installed application, so no dock entry is created. To pin it: add a
  `~/.local/share/applications/modelink.desktop` and extend the `launchers` list
  in `scripts/layout.js`.
- **GTK light theme:** installed Orchis GTK themes are dark-only, so light mode
  maps GTK apps to native `Breeze`. Firefox/Chrome/VSCode draw their own UI.

## 10. Verification checklist (`./verify.sh`)

Desktop (clean containment, wallpaper) · top bar (global menu, tray, clock,
pager) · dock (launcher, icontasks, trash, floating, fit-to-content) · exactly
two panels · kwin (Orchis decoration, 4 desktops, blur on, wobbly off) · theme
(LNF, colors, icons, cursor, font) · GTK wiring · backup present.

Manual checks after apply: global menu shows app menus (File/Edit/View…),
tray icon actions work, clock updates, pinned dock apps launch, running apps
show indicators, trash works, fullscreen covers the screens cleanly, dual
monitor panels stay on the primary screen.