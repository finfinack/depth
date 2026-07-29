import Toybox.Application;
import Toybox.Lang;
import DepthCore;

// Storage keys. Application.Storage is scoped to the app ID, so these are
// private to this app — the two data fields are separate Connect IQ apps with
// their own stores and cannot see or be seen by these.
const SESSION_MAX = "lastMaxDepth";
const SESSION_DIVES = "lastDives";
const SESSION_BOTTOM = "lastBottomTime";

//! What the last outing came to, as the Last Session page shows it.
//!
//! "Session" here means one run of this app, not one recorded activity. The app
//! cannot see what the data fields recorded during an activity — separate app
//! IDs, no shared storage — so this is the last time somebody opened the app and
//! actually went under, which for anyone using the app in the water is the same
//! thing. Recorded activities get the same numbers from the FIT file instead.
class depthSession {

    public var max_depth as Float;
    public var dive_count as Number;
    public var bottom_time as Number;

    function initialize(maximum as Float, dives as Number, bottom as Number) {
        max_depth = maximum;
        dive_count = dives;
        bottom_time = bottom;
    }
}

//! Read the stored session, or null when there is not one to read.
//!
//! Every field is type-checked rather than cast. Storage survives app updates,
//! so what comes back was written by some earlier version of this app and is
//! not to be trusted to still be the shape it was written in — a bad cast here
//! would crash the app on launch, which is the worst place for it.
function loadSession() as depthSession? {
    try {
        var maximum = Storage.getValue(SESSION_MAX);
        var dives = Storage.getValue(SESSION_DIVES);
        var bottom = Storage.getValue(SESSION_BOTTOM);

        if (!(maximum instanceof Lang.Float) || !(dives instanceof Lang.Number)
                || !(bottom instanceof Lang.Number)) {
            return null;
        }
        // A stored session always had a dive in it — see saveSession(). One
        // that claims otherwise was not written by this code.
        if (dives <= 0 || bottom < 0) {
            return null;
        }
        return new depthSession(maximum, dives, bottom);
    } catch (e) {
        return null;
    }
}

//! Store this run as the last session, if it is worth storing.
//!
//! **Only a run that recorded a dive is stored.** That is what keeps the page
//! honest: opening the app to check the weather, or to look at the last session
//! itself, counts no dives and so writes nothing, and the real outing survives.
//! Without this guard the page would overwrite itself with an empty session
//! every time it was read, and could never show a real one.
//!
//! The other half of that guard is in depthApp.onStop(), which only calls this
//! when the full app actually ran: glance mode never reaches getInitialView(),
//! so its model is null and a glance cannot overwrite anything either.
function saveSession(model as DepthModel) as Void {
    var maximum = model.max_depth;
    if (model.dive_count <= 0 || maximum == null) {
        return;
    }
    try {
        Storage.setValue(SESSION_MAX, maximum);
        Storage.setValue(SESSION_DIVES, model.dive_count);
        Storage.setValue(SESSION_BOTTOM, model.bottom_time);
    } catch (e) {
        // Nothing useful to do at app exit, and nothing worth crashing over:
        // the previous session simply stays as the stored one.
    }
}

//! Milliseconds as a duration carrying its own units: "42s", "2m 14s", "1h 05m".
//!
//! Units rather than the bare "2:14" a stopwatch would show. Every other value
//! on these pages says what it is — a depth carries "m" or "ft" — and a colon
//! alone does not: "2:14" is two minutes and fourteen seconds or two hours and
//! fourteen minutes depending on what the reader assumes, and a session's
//! bottom time is plausibly either. Padding to "0:02:14" would disambiguate it
//! by shape, but costs more width than the units do and reads as a stopwatch
//! rather than a total.
//!
//! Seconds are dropped past an hour: at that length they are noise, and the
//! row has to share its width with a label.
//!
//! Not localised. "h", "m" and "s" are the same in all five languages this
//! ships in, and the label beside it says which quantity they belong to.
function formatDuration(milliseconds as Number) as String {
    var total = milliseconds / 1000;
    var hours = total / 3600;
    var minutes = (total / 60) % 60;
    var seconds = total % 60;

    if (hours > 0) {
        return hours.format("%d") + "h " + minutes.format("%02d") + "m";
    }
    if (minutes > 0) {
        return minutes.format("%d") + "m " + seconds.format("%02d") + "s";
    }
    return seconds.format("%d") + "s";
}
