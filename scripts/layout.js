// kde-macos-config — panel layout script (Plasma 6 native scripting API)
//
// This script is executed by plasmashell via:
//   org.kde.PlasmaShell.evaluateScript (D-Bus)
// It is IDEMPOTENT: every existing panel is removed first, then the two
// macOS-inspired panels are created from scratch. This matches the exact API
// used by Plasma's own "New Panel" layout templates (see
// /usr/share/plasma/layout-templates/org.kde.plasma.desktop.defaultPanel/contents/layout.js).
//
// Only stable, documented scripting API calls are used. No config-file surgery.

var log = [];

// ---- Phase 1: clear the slate (this layout owns the panels) ----
locked = false;

var ids = panelIds.slice();
for (var i = 0; i < ids.length; i++) {
    var p = panelById(ids[i]);
    if (p) {
        var loc = p.location;
        p.remove();
        log.push("removed panel @ " + loc);
    }
}

// ---- Phase 2: TOP MENU BAR (macOS menu bar analog) ----
// Flush, full-width, 30 px tall. Left: global menu. Center: workspace pager.
// Right: system tray + clock. Native widgets only.
var topPanel = new Panel;
topPanel.location = "top";
topPanel.height = Math.round(gridUnit * 10 / 6);   // = 30 px at gridUnit 18
topPanel.floating = false;                          // flush against the screen edge
topPanel.offset = 0;
// Panel visibility is deliberately NOT set here: the scripting API drops
// visibility assignments silently. apply.sh writes the real, Plasma-owned key
// ([PlasmaViews][Panel N] panelVisibility) after this script runs, and
// verify.sh asserts it — so setting it here would only be dead code.

topPanel.addWidget("org.kde.plasma.appmenu");       // Global Menu (app menus + fallback)
topPanel.addWidget("org.kde.plasma.panelspacer");
topPanel.addWidget("org.kde.plasma.pager");         // subtle workspace indicator (center)
topPanel.addWidget("org.kde.plasma.panelspacer");
topPanel.addWidget("org.kde.plasma.systemtray");    // network / bluetooth / audio / battery ...
topPanel.addWidget("org.kde.plasma.digitalclock");
log.push("top bar ok (" + topPanel.location + ", h=" + topPanel.height + ")");

// ---- Phase 3: BOTTOM DOCK (macOS dock analog) ----
// Floating, centered, compact, fit-to-content. Launcher | apps | divider | Trash.
var dock = new Panel;
dock.location = "bottom";
dock.height = Math.round(gridUnit * 26 / 9);        // = 52 px at gridUnit 18
dock.floating = true;                               // floating visual (rounded, margins)
dock.offset = 0;                                    // visibility set by apply.sh, see above
dock.alignment = "center";                          // centered on the screen
dock.minimumLength = -1;                            // "fit content" (shrinks to the icons)
dock.maximumLength = -1;

dock.addWidget("org.kde.plasma.kickoff");           // launcher at the beginning

var tasks = dock.addWidget("org.kde.plasma.icontasks");   // Icons-only Task Manager (native)
tasks.currentConfigGroup = ["General"];

// The pinned launcher list is injected by apply.sh, which resolves every id
// against the desktop files actually installed here (scripts/resolve-launchers.sh)
// before handing it over. Do NOT hardcode ids here: an id with no desktop file
// makes Plasma draw a generic "Unknown application" tile, and because this script
// rewrites the whole list on every apply, that tile cannot be unpinned by hand.
// The list itself lives in scripts/dock-launchers.list.
var PINNED_RAW = "@DOCK_LAUNCHERS@";
if (PINNED_RAW.indexOf("@") !== -1) {
    // Substitution did not happen. Leave the dock exactly as it is rather than
    // guess: pinning an unverified id is worse than pinning none, and clearing
    // the list would silently empty the user's dock.
    log.push("dock launchers: @DOCK_LAUNCHERS@ not substituted - leaving them untouched");
} else {
    var PINNED = PINNED_RAW.split(",");
    tasks.writeConfig("launchers", PINNED.join(","));
    log.push("dock launchers (" + PINNED.length + "): " + PINNED.join(" "));
}
tasks.reloadConfig();
tasks.writeConfig("separateLaunchers", true);       // pinned != running, visually distinct
tasks.reloadConfig();

dock.addWidget("org.kde.plasma.marginsseparator");  // subtle divider before Trash
dock.addWidget("org.kde.plasma.trash");             // trash at the far end
log.push("dock ok (" + dock.location + ", h=" + dock.height + ")");

// Report the panel ids we just created. apply.sh cannot reliably guess them:
// removing all panels and recreating them assigns BRAND NEW ids, and plasmashell
// flushes plasmashellrc asynchronously, so the ids on disk lag behind the live
// ones. Writing panelVisibility to the stale on-disk ids silently does nothing -
// which is exactly how the setting appeared to apply but never took effect.
log.push("panelIds=" + topPanel.id + "," + dock.id);

locked = true;                                      // match distro default (widgets locked)
log.push("layout complete");
print(log.join("|"));
