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
topPanel.hiding = "normal";                         // always visible, windows may cover it
topPanel.offset = 0;

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
dock.hiding = "normal";                             // no auto-hide surprises in fullscreen
dock.offset = 0;
dock.alignment = "center";                          // centered on the screen
dock.minimumLength = -1;                            // "fit content" (shrinks to the icons)
dock.maximumLength = -1;

dock.addWidget("org.kde.plasma.kickoff");           // launcher at the beginning

var tasks = dock.addWidget("org.kde.plasma.icontasks");   // Icons-only Task Manager (native)
tasks.currentConfigGroup = ["General"];
tasks.writeConfig(
    "launchers",
    "applications:org.kde.dolphin.desktop," +       // Finder equivalent
    "applications:org.kde.konsole.desktop," +       // Terminal
    "applications:org.mozilla.firefox.desktop," +   // Browser
    "applications:com.google.Chrome.desktop," +     // Browser
    "applications:code.desktop");                   // IDE
tasks.reloadConfig();
tasks.writeConfig("separateLaunchers", true);       // pinned != running, visually distinct
tasks.reloadConfig();

dock.addWidget("org.kde.plasma.marginsseparator");  // subtle divider before Trash
dock.addWidget("org.kde.plasma.trash");             // trash at the far end
log.push("dock ok (" + dock.location + ", h=" + dock.height + ")");

locked = true;                                      // match distro default (widgets locked)
log.push("layout complete");
print(log.join("|"));