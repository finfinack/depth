import Toybox.Attention;
import Toybox.Lang;
import Toybox.System;

// One pulse per boundary, so the buzz says which one was crossed without
// anything to read: one for the first colour band, two for the second, three
// for the third. Short and firm rather than long and soft — it has to be felt
// through a wetsuit sleeve, and it is a cue rather than an alarm.
//
// The pattern is at most three pulses and two gaps, well inside the eight
// VibeProfiles Attention.vibrate() accepts.
const BAND_VIBE_DUTY = 75;    // percent
const BAND_VIBE_LENGTH = 250; // ms
const BAND_VIBE_GAP = 200;    // ms

// Longest pattern built, which is also profileBands()' length. Bounded here
// as well because the count arrives from the model and the API has a limit.
const BAND_VIBE_MAX = 3;

//! Buzz `count` times, for a colour band boundary just crossed on the way down.
//!
//! Silent where the watch has no vibration motor, and silent where the user has
//! turned vibration off system wide — an alert somebody has switched off on the
//! watch must not arrive anyway because it came from an app.
//!
//! This lives in the app rather than in the barrel because only the app raises
//! it. A data field could — Toybox.Attention is open to them — but the four
//! fields are meant to be run together and cannot see each other, so a buzz in
//! the barrel would fire once per field that happened to be on a data screen.
//! The glance is out for a different reason: it is built and thrown away for
//! every draw, so it never has two samples to find a crossing between.
function alertBandCrossing(count as Number) as Void {
    if (count < 1 || !(Attention has :vibrate)) {
        return;
    }
    if (!System.getDeviceSettings().vibrateOn) {
        return;
    }
    if (count > BAND_VIBE_MAX) {
        count = BAND_VIBE_MAX;
    }

    var pattern = [] as Array<Attention.VibeProfile>;
    for (var pulse = 0; pulse < count; pulse += 1) {
        if (pulse > 0) {
            pattern.add(new Attention.VibeProfile(0, BAND_VIBE_GAP));
        }
        pattern.add(new Attention.VibeProfile(BAND_VIBE_DUTY, BAND_VIBE_LENGTH));
    }
    Attention.vibrate(pattern);
}
