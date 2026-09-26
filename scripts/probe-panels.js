// kde-macos-config — shared panels probe (Plasma 6 scripting API)
//
// Single source of truth for "what panels/widgets exist right now", used by
// both detect.sh (human inventory) and verify.sh (PASS/FAIL checks).
//
// Output (one line per panel, '|'-joined; parse in bash):
//   count=<n>|panelids=<id,...>|panelids|<location>;h=<height>;float=<true|false>;widgets=<type,...>
// Locations are the stable Plasma strings: top|bottom|left|right|desktop.
//
// panelids= is the LIVE panel id set. Callers need it because plasmashellrc on
// disk lags the running shell and can transiently contain [PlasmaViews][Panel N]
// sections for panels that no longer exist; only the live ids describe reality.

var log = [];

var ids = panelIds.slice();
log.push("count=" + ids.length);
log.push("panelids=" + ids.join(","));
for (var i = 0; i < ids.length; i++) {
    var p = panelById(ids[i]);
    if (!p) { continue; }
    var wtypes = [];
    var wids = p.widgetIds;
    for (var w = 0; w < wids.length; w++) {
        var wid = p.widgetById(wids[w]);
        if (wid) { wtypes.push(wid.type); }
    }
    log.push(p.location + ";h=" + Math.round(p.height) + ";float=" + p.floating +
             ";widgets=" + wtypes.join(","));
}

print(log.join("|"));