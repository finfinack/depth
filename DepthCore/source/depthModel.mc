import Toybox.Activity;
import Toybox.Application;
import Toybox.Lang;
import Toybox.System;

module DepthCore {

    //! Values of DepthModel.trend. Module scope rather than class constants,
    //! because a class constant in Monkey C is only reachable through an
    //! instance and these are part of what the barrel exposes.
    (:glance) const TREND_LEVEL = 0;
    (:glance) const TREND_DESCENDING = 1;
    (:glance) const TREND_ASCENDING = 2;

    //! Depth derived from barometric pressure, relative to a tracked surface
    //! pressure baseline.
    //!
    //! The baseline is the lowest pressure seen in a trailing window of samples
    //! taken while the watch looked like it was at the surface. Two properties
    //! matter, and both exist to fix the ratcheting min-hold this replaced:
    //!
    //! - The window is *trailing*, so a single spuriously low sample stops
    //!   affecting the reading once it ages out instead of biasing every later
    //!   reading for the rest of the session.
    //! - The window is *frozen* while the watch looks submerged, so a long dive
    //!   cannot drag the baseline down with it.
    //!
    //! If that frozen state lasts implausibly long the baseline is probably
    //! wrong, and the model says so — `baseline_stale` — but it does not act on
    //! it. This used to start the baseline over from the current pressure, and
    //! that was the wrong trade in both directions:
    //!
    //! - Every error it corrected ran the *safe* way. A baseline can only get
    //!   stuck too low, because every path but rebaseline() derives it from a
    //!   trailing minimum, and too low reads too deep.
    //! - The correction itself ran the dangerous way: re-zeroing at depth reads
    //!   0.00 while submerged, which is indistinguishable from a watch that is
    //!   simply working, and silently understates every reading after it.
    //!
    //! Real dive computers zero at the surface and *indicate* a suspect
    //! baseline; none of them re-zero mid-dive. A stuck baseline announces
    //! itself anyway — a watch showing depth in air is obviously wrong — so
    //! warning and leaving the number alone loses nothing and risks nothing.
    //!
    //! The window is two half-window buckets rather than a ring of samples: the
    //! effective window is therefore somewhere between one and two bucket
    //! lengths, which is all the precision this needs and costs two floats.
    //!
    //! Note the thresholds below are engineering estimates, not measured
    //! values. They want revisiting once the barometer's actual behaviour under
    //! water has been checked on a real device.
    (:glance)
    class DepthModel {

        const feet_per_meter = 3.28084;

        // Pascal per meter of water. Fresh water is the physical value for rho=1000.
        // Salt water uses the EN13319 convention of 1 msw = 10000 Pa exactly rather
        // than the ~10052 Pa that rho=1030 gives, so readings agree with what a dive
        // computer or a dive table shows. The difference is about 10 cm at 20 m,
        // well inside this sensor's error.
        const fresh_water_pressure = 9806.65;
        const salt_water_pressure = 10000.0;

        // Values of the waterType and unitOverride settings.
        const WATER_FRESH = 0;
        const WATER_SALT = 1;
        const UNITS_AUTO = 0;
        const UNITS_METRIC = 1;
        const UNITS_STATUTE = 2;

        // Depth below which the watch counts as being at the surface, in pascal.
        // 0.30 m of water; wave action and sensor noise both live inside this, and
        // readings this shallow are not meaningful anyway.
        const surface_band = 2942.0;

        // Half of the trailing baseline window, so the window itself is 1.5-3 min.
        const bucket_duration = 90000; // ms

        // How long the watch may look submerged before the baseline is called
        // suspect rather than the depth being real. Only ever raises a warning
        // — see the class comment for why it no longer corrects anything.
        const max_submerged = 600000; // ms

        // Fastest descent treated as a real one. Anything quicker is a sensor
        // glitch, and must not be allowed to reach the maximum.
        const max_descent_rate = 3.0; // m/s

        // How much faster than the descent already under way a sample may be
        // and still count as part of it — the acceleration allowance in
        // updateMaximum(). Deliberately tight: being too tight only delays a
        // new maximum by one sample, since a diver who is really going down
        // keeps going down, while being too loose lets a spike in permanently.
        const max_rate_step = 0.5; // m/s

        // How fast the depth has to be changing before the trend commits to a
        // direction, and how slow before it goes back to level. Two thresholds
        // rather than one because a single one makes the trend chatter every
        // time the rate grazes it, which on screen is a flickering indicator.
        const trend_commit = 0.15; // m/s
        const trend_release = 0.08; // m/s

        // A pressure sample this close to the one before it did not come from a
        // live sensor: a barometer's own noise is several pascal, so a run of
        // readings this tight means the value is pinned rather than measured.
        const flat_pressure = 0.5; // Pa

        // How many consecutive flat samples before the sensor is called
        // saturated. Eight seconds at the 1 Hz this is fed at: long enough that
        // a quiet sensor and a still wrist do not trip it, short enough to warn
        // while the diver is still down there.
        const flat_samples = 8;

        // Shallowest reading a saturation claim is made at. Above this the
        // watch is plausibly just sitting still in air, where a flat pressure
        // means nothing. Set below the ~0.9 m a wearable barometer is rated to,
        // so a sensor that pins early is still caught.
        const saturation_depth = 0.5; // m

        // Weight of the newest sample in the rolling rate below. Roughly a
        // three second time constant at the 1 Hz this is fed at: long enough to
        // ride out sensor noise, short enough to still feel immediate. A single
        // sample difference is almost entirely noise at this sample rate, so
        // the rate has to be smoothed even though the depth itself is not.
        const trend_smoothing = 0.3;

        //! Current depth in meters, or null while no pressure reading is available.
        var depth as Float?;
        //! Deepest reading in meters so far, or null before the first reading.
        var max_depth as Float?;

        //! The same, but taking every sample as it came — no spike rejection of
        //! any kind. Recorded into the FIT file and shown nowhere: it is there
        //! so a session can be checked afterwards, since the true peak is
        //! somewhere between this and max_depth. A second maximum on screen
        //! would only raise the question of which one is real.
        var max_depth_raw as Float?;
        //! Which way the depth is going: one of the TREND_ values above.
        var trend as Number = TREND_LEVEL;
        //! The pressure the current depth was derived from, in pascal, exactly as
        //! the sensor reported it. Null while no reading is available.
        var pressure as Float?;

        //! Whether the pressure reading looks pinned at the sensor's ceiling
        //! rather than following the water. While this is set, `depth` is a
        //! lower bound and not a measurement. See updateSaturation().
        var saturated as Boolean = false;

        //! Whether the sensor has looked saturated at any point since the last
        //! re-zero, which makes `max_depth` a lower bound too — a maximum
        //! reached while the reading was pinned is the ceiling, not the dive.
        var saturation_seen as Boolean = false;

        //! Whether the watch has looked submerged for so long that the surface
        //! baseline is more likely wrong than the depth real. Nothing is
        //! corrected — every reading stays exactly what the sensor supports —
        //! but readings taken against a suspect baseline are marked, because a
        //! baseline that is off makes the depth off by the same amount.
        //!
        //! Unlike saturation there is no separate flag for the maximum: this
        //! describes the baseline, and the live depth and the maximum are both
        //! measured from it, so it applies to both equally.
        var baseline_stale as Boolean = false;

        var unit as System.UnitsSystem = System.UNIT_METRIC; // or System.UNIT_STATUTE
        var water_pressure as Float = fresh_water_pressure;

        //! Which set of colour bands depthColor() should use: one of the
        //! PROFILE_ values. Read here because this is where the settings are
        //! read; nothing in the model itself uses it, and the data fields never
        //! colour anything.
        var color_profile as Number = PROFILE_SNORKEL;

        private var _baseline as Float?;

        // The two halves of the trailing window, each holding its lowest pressure.
        private var _min_current as Float?;
        private var _min_previous as Float?;
        private var _bucket_start as Number = 0;

        // When the watch first looked submerged, for the watchdog above.
        private var _submerged_since as Number?;

        // The previous sample, used to confirm a new maximum and to keep a lone
        // low reading out of the baseline window.
        private var _previous_depth as Float?;
        private var _previous_time as Number = 0;
        private var _previous_pressure as Float?;

        // ...and whether that previous sample was at the surface, which is what
        // makes it a candidate surface pressure. See where confirmed is worked
        // out in updateAt().
        private var _previous_at_surface as Boolean = false;

        // The sample before that. Two are needed rather than one because
        // updateMaximum() judges a sample against the rate leading into it,
        // and a rate needs two samples of its own.
        private var _previous2_depth as Float?;
        private var _previous2_time as Number = 0;

        // Smoothed rate of change in m/s, positive going deeper, behind trend.
        private var _rate as Float = 0.0;

        // How many samples in a row have not moved, behind saturated.
        private var _flat_count as Number = 0;

        function initialize() {
            loadSettings();
        }

        //! Read the app settings. Called once at startup and again whenever the app
        //! is told they changed, so the long-lived app and glance pick a change
        //! up without being restarted.
        function loadSettings() as Void {
            water_pressure = (numberSetting("waterType", WATER_FRESH) == WATER_SALT)
                ? salt_water_pressure
                : fresh_water_pressure;

            // An app that never declares this key — both data fields, which
            // colour nothing — gets the default without having to.
            color_profile = numberSetting("colorProfile", PROFILE_SNORKEL);

            var units = numberSetting("unitOverride", UNITS_AUTO);
            if (units == UNITS_METRIC) {
                unit = System.UNIT_METRIC;
            } else if (units == UNITS_STATUTE) {
                unit = System.UNIT_STATUTE;
            } else {
                // Depth is a vertical distance in the environment, so it follows the
                // elevation unit setting rather than the (body) height setting.
                unit = System.getDeviceSettings().elevationUnits;
            }

            // Re-zero is a trigger rather than a state, so it is acted on and then
            // switched off again. This is the only way into a re-zero for the data
            // fields, which have no input of their own.
            if (booleanSetting("rezero", false)) {
                rezero();
                Properties.setValue("rezero", false);
            }
        }

        //! Read the pressure out of the given activity info and update the current
        //! and the maximum depth.
        function update(info as Activity.Info) as Void {
            updateAt(info, System.getTimer());
        }

        //! update() with the clock supplied, which is the only way the tests can
        //! make time pass: every interval this class cares about is minutes
        //! long, and two update() calls in a row are microseconds apart — which
        //! is exactly the case the trend and the maximum both refuse to act on.
        //! The baseline window, the submerged watchdog and the trend hysteresis
        //! carry most of the risk here and are untestable without this seam.
        //!
        //! `now` is a millisecond counter that may wrap, as System.getTimer()
        //! does; going backwards is handled wherever it is compared.
        function updateAt(info as Activity.Info, now as Number) as Void {
            // See Activity.Info in the documentation for available information.
            // - ambientPressure as Lang.Float or Null
            //   The ambient pressure in Pascals (Pa).
            // - rawAmbientPressure as Lang.Float or Null
            //   The raw ambient pressure in Pascals (Pa).
            // rawAmbientPressure is read straight from the sensor (temperature
            // compensated). ambientPressure is smoothed by a two-stage filter,
            // which lags during a fast descent, so it is only a fallback for
            // devices/contexts where the raw value is not populated.
            var pressure = info.rawAmbientPressure;
            if (pressure == null) {
                pressure = info.ambientPressure;
            }
            self.pressure = pressure;
            if (pressure == null) {
                depth = null;
                // Whatever the depth was doing, it is not doing it any more.
                trend = TREND_LEVEL;
                _rate = 0.0;
                // A reading that is not there cannot be pinned. saturation_seen
                // is left alone: it describes the session, not this sample.
                saturated = false;
                _flat_count = 0;
                // The samples either side of a gap are not neighbours. Left in
                // place, the first reading back gets judged for a maximum, a
                // rate and a baseline outlier against one from before the gap,
                // which may be minutes old and anywhere.
                forgetNeighbours();
                return;
            }

            var baseline = _baseline;
            if (baseline == null) {
                rebaseline(pressure, now);
                baseline = pressure;
            }

            // The window is fed the higher of this sample and the last one, so a
            // single low outlier cannot pull the baseline down. Without this, one
            // bad sample makes the watch look permanently submerged, which freezes
            // the window on the bad value and leaves the watchdog below as the only
            // way out — ten minutes of phantom depth.
            //
            // Only a previous sample that was itself at the surface counts. A
            // submerged one is not a candidate surface pressure at all, and
            // feeding it here anchors the baseline at depth: surfacing from a
            // submersion longer than a full window rotates the window empty,
            // so that stale high reading becomes the only value in it. Dive
            // again on the next sample and the watch reads 0.00 at depth, with
            // the baseline pinned there until it surfaces twice in a row.
            var previous_pressure = _previous_pressure;
            var confirmed = (_previous_at_surface && previous_pressure != null
                    && previous_pressure > pressure)
                ? previous_pressure
                : pressure;
            _previous_pressure = pressure;

            if (pressure - baseline <= surface_band) {
                // At the surface: the window tracks the surface pressure, so
                // whatever the baseline was, it is being measured again.
                _submerged_since = null;
                baseline_stale = false;
                _previous_at_surface = true;
                feedWindow(confirmed, now);
                baseline = windowMinimum(confirmed);
                _baseline = baseline;
            } else {
                _previous_at_surface = false;
                // Submerged: the window is frozen, so the dive cannot pull the
                // baseline down after it. Long enough and the baseline is the
                // likelier culprit — but say so rather than acting on it, since
                // acting means re-zeroing at depth. See the class comment.
                var since = _submerged_since;
                if (since == null || now < since) {
                    // Null is the first submerged sample; going backwards is
                    // the millisecond counter wrapping, and an interval that
                    // cannot be measured must not be called implausible.
                    _submerged_since = now;
                } else if (now - since > max_submerged) {
                    baseline_stale = true;
                }
            }

            var value = (pressure - baseline) / water_pressure;
            if (value < 0.0) {
                value = 0.0;
            }
            depth = value;
            updateSaturation(previous_pressure, pressure, value);
            // Must come before updateMaximum(), which overwrites the previous
            // sample this reads.
            updateTrend(value, now);
            updateMaximum(value, now);
        }

        //! Drop the baseline and the maximum and start measuring again from the
        //! next sample. Needed when the watch was already submerged, or at a
        //! different altitude, when measuring started.
        function rezero() as Void {
            _baseline = null;
            _min_current = null;
            _min_previous = null;
            _submerged_since = null;
            forgetNeighbours();
            _flat_count = 0;
            depth = null;
            max_depth = null;
            max_depth_raw = null;
            trend = TREND_LEVEL;
            pressure = null;
            saturated = false;
            saturation_seen = false;
            baseline_stale = false;
        }

        //! Format a depth in meters as a bare number in the user's unit, without a
        //! unit suffix. Returns "n/a" when the depth is unknown.
        function formatDepth(meters as Float?) as String {
            if (meters == null) {
                return "n/a";
            }
            if (unit == System.UNIT_METRIC) {
                return meters.format("%.2f");
            }
            return (meters * feet_per_meter).format("%.1f");
        }

        //! formatDepth() with a ">=" in front when the reading is a lower bound
        //! rather than a measurement — see updateSaturation(). "n/a" is left
        //! alone: there is nothing to bound.
        //!
        //! ASCII rather than "≥" on purpose. The built-in fonts have patchy
        //! glyph coverage and a missing glyph draws an empty box, which would
        //! turn the warning into a puzzle. Same reason the trend indicator is a
        //! polygon rather than an arrow character.
        function formatBounded(meters as Float?, limited as Boolean) as String {
            var text = formatDepth(meters);
            return (limited && meters != null) ? ">=" + text : text;
        }

        //! The mark that goes on the *end* of a reading whose baseline is
        //! suspect — after the unit, since it qualifies the whole thing.
        //!
        //! Deliberately not part of formatBounded(): that prefix belongs
        //! against the number, and these two say opposite things. ">=" means
        //! the depth is at least this much; "?" means it may be less, because
        //! a baseline that is off puts every reading off by the same amount.
        //! Both can be true at once, and ">=6.40 m?" is then honest.
        function staleMark(meters as Float?) as String {
            return (baseline_stale && meters != null) ? "?" : "";
        }

        //! The unit suffix matching formatDepth().
        function unitLabel() as String {
            return (unit == System.UNIT_METRIC) ? "m" : "ft";
        }

        //! Read a setting, or null if the app never declared it.
        //!
        //! Properties.getValue() throws on a key that is not in the app's
        //! properties.xml, and this class is constructed by every app that
        //! embeds the barrel. Taking the host app down over a missing settings
        //! key would be the wrong trade: a key the app does not declare is a key
        //! the user cannot set, which is the same situation as one left at its
        //! default. So the exception is turned into the default, and the app
        //! keeps running with the barrel's own idea of the setting.
        //!
        //! It also means a setting added here does not have to be declared by
        //! every consuming app at once.
        private function rawSetting(key as String) as Object? {
            try {
                return Properties.getValue(key);
            } catch (e) {
                return null;
            }
        }

        //! Read a numeric setting, falling back if it is missing or the wrong type.
        private function numberSetting(key as String, fallback as Number) as Number {
            var value = rawSetting(key);
            if (value instanceof Lang.Number) {
                return value;
            }
            return fallback;
        }

        //! Read a boolean setting, falling back if it is missing or the wrong type.
        private function booleanSetting(key as String, fallback as Boolean) as Boolean {
            var value = rawSetting(key);
            if (value instanceof Lang.Boolean) {
                return value;
            }
            return fallback;
        }

        //! Start the baseline over from a single sample.
        //!
        //! Every reading is measured from the baseline, so replacing it makes
        //! everything derived from the old one meaningless — the neighbours the
        //! maximum and the rate are judged against most of all. Both callers
        //! happen to have cleared those already, but the invariant belongs here
        //! rather than in whoever calls next.
        private function rebaseline(pressure as Float, now as Number) as Void {
            _baseline = pressure;
            _min_current = pressure;
            _min_previous = null;
            _bucket_start = now;
            _submerged_since = null;
            baseline_stale = false;
            forgetNeighbours();
        }

        //! Drop the remembered samples, so the next reading is judged on its
        //! own rather than against one across a discontinuity.
        private function forgetNeighbours() as Void {
            _previous_depth = null;
            _previous_time = 0;
            _previous_pressure = null;
            _previous_at_surface = false;
            _previous2_depth = null;
            _previous2_time = 0;
            _rate = 0.0;
        }

        //! Add a surface sample to the trailing window, rotating the buckets as
        //! time passes.
        private function feedWindow(pressure as Float, now as Number) as Void {
            var elapsed = now - _bucket_start;
            // A negative elapsed means the millisecond counter wrapped; treat it
            // like a rotation rather than letting the window freeze forever.
            if (elapsed < 0 || elapsed >= bucket_duration) {
                // Both halves are stale if more than a full window has passed,
                // which is what happens on surfacing from a long dive.
                _min_previous = (elapsed < 0 || elapsed >= 2 * bucket_duration) ? null : _min_current;
                _min_current = null;
                _bucket_start = now;
            }

            var current = _min_current;
            if (current == null || pressure < current) {
                _min_current = pressure;
            }
        }

        //! The lowest pressure held in the window, falling back to the given
        //! pressure while the window is empty.
        private function windowMinimum(fallback as Float) as Float {
            var minimum = _min_current;
            if (minimum == null) {
                minimum = fallback;
            }
            var previous = _min_previous;
            if (previous != null && previous < minimum) {
                minimum = previous;
            }
            return minimum;
        }

        //! Decide whether the pressure reading is pinned at the sensor's
        //! ceiling rather than following the water.
        //!
        //! A watch barometer is built for weather and altitude. The parts used
        //! are rated to around 1100 hPa, which is only about 0.9 m of water
        //! above a sea-level surface, and Garmin's firmware is reported to
        //! clamp the value it hands out well before the sensor itself gives up.
        //! Past whichever comes first the reading stops rising however much
        //! deeper the diver goes — and nothing about the number says so. It is
        //! the one failure this app can neither measure around nor survive
        //! quietly, because it reads *shallow*, which is the direction that
        //! misleads rather than alarms.
        //!
        //! What gives it away is the absence of noise. A live barometer jitters
        //! by several pascal from one sample to the next; a pinned one repeats
        //! itself. So a run of samples that agree to within a fraction of a
        //! pascal, taken deep enough that the watch is certainly in water, is a
        //! sensor that has stopped measuring rather than water that has stopped
        //! moving.
        //!
        //! Note what this cannot do: it detects the ceiling, it does not lift
        //! it. Once the flag is set the depth is a lower bound and that is all
        //! it will ever be.
        private function updateSaturation(previous as Float?, pressure as Float,
                                          value as Float) as Void {
            if (previous == null || value < saturation_depth) {
                _flat_count = 0;
                saturated = false;
                return;
            }

            var change = pressure - previous;
            if (change < 0.0) {
                change = -change;
            }
            if (change >= flat_pressure) {
                _flat_count = 0;
                saturated = false;
                return;
            }

            if (_flat_count < flat_samples) {
                _flat_count += 1;
            }
            if (_flat_count >= flat_samples) {
                saturated = true;
                saturation_seen = true;
            }
        }

        //! Track which way the depth is going, for the trend indicator.
        //!
        //! Must be called before updateMaximum(), which overwrites the previous
        //! sample this reads.
        //!
        //! The depth itself is never smoothed — it is the raw pressure against
        //! the tracked baseline. Its *rate of change* has to be, because one
        //! sample of difference at 1 Hz is far smaller than the sensor's own
        //! noise, and an indicator driven off that would just flicker.
        private function updateTrend(value as Float, now as Number) as Void {
            var previous = _previous_depth;
            if (previous == null) {
                return; // A rate needs two samples.
            }

            var seconds = (now - _previous_time) / 1000.0;
            if (seconds <= 0.0) {
                return; // No time passed, or the millisecond counter wrapped.
            }

            var instant = (value - previous) / seconds;
            if (instant > max_descent_rate || instant < -max_descent_rate) {
                return; // Quicker than any real movement, so it is a glitch.
            }

            _rate += trend_smoothing * (instant - _rate);

            // Commit at the higher threshold and release at the lower one,
            // holding the current direction in between.
            if (_rate >= trend_commit) {
                trend = TREND_DESCENDING;
            } else if (_rate <= -trend_commit) {
                trend = TREND_ASCENDING;
            } else if (_rate > -trend_release && _rate < trend_release) {
                trend = TREND_LEVEL;
            }
        }

        //! Track the deepest reading, guarded against noise.
        //!
        //! A spike and a real peak look identical from one sample: both are a
        //! single reading deeper than the two around it. This used to keep the
        //! shallower of each consecutive pair, which rejects every spike — and
        //! clips every genuine peak by a full sample of descent rate with it,
        //! about a metre at a 1 m/s freedive turn. Reading a metre shallow than
        //! the diver actually went is the wrong way round to be wrong.
        //!
        //! What tells the two apart is not the sample, it is what leads into
        //! it. A real peak sits at the end of a descent, so it is roughly where
        //! the rate already established predicts. A spike appears out of a
        //! series going nowhere. So a sample is accepted as a maximum when it
        //! is no deeper than the run-in explains, and the peak itself is kept
        //! rather than its neighbour.
        //!
        //! This is strictly the stronger guard, not a relaxation: a 3 m jump in
        //! one second sits exactly on max_descent_rate and slips past the rate
        //! check below, but not past the run-in.
        private function updateMaximum(value as Float, now as Number) as Void {
            // The raw maximum takes every sample, including the ones the guards
            // below throw away. That is what makes it worth recording: the gap
            // between the two is either a peak this lost or a spike it caught,
            // and the pressure series says which.
            var raw = max_depth_raw;
            if (raw == null || value > raw) {
                max_depth_raw = value;
            }

            var previous = _previous_depth;
            var previous_time = _previous_time;
            var older = _previous2_depth;
            var older_time = _previous2_time;

            _previous2_depth = previous;
            _previous2_time = previous_time;
            _previous_depth = value;
            _previous_time = now;

            if (previous == null) {
                return; // Nothing to judge this against yet.
            }

            var seconds = (now - previous_time) / 1000.0;
            if (seconds <= 0.0) {
                return; // No time passed, or the millisecond counter wrapped.
            }

            var step = value - previous;
            if (step > max_descent_rate * seconds) {
                return; // Faster than any real descent, so treat it as a glitch.
            }

            // How much deeper this sample may be before it stops looking like
            // the continuation of a descent. The run-in carries most of it;
            // max_rate_step is the slack on top for real acceleration.
            //
            // An ascending run-in contributes nothing rather than a negative
            // allowance: turning round and going down again is ordinary, and
            // the slack alone is enough to cover the first sample of it.
            var allowed = max_rate_step * seconds;
            if (older != null) {
                var run_seconds = (previous_time - older_time) / 1000.0;
                if (run_seconds > 0.0) {
                    var rate = (previous - older) / run_seconds;
                    if (rate > 0.0) {
                        allowed += rate * seconds;
                    }
                }
            }
            if (step > allowed) {
                return; // Deeper than the run-in explains: a spike, not a peak.
            }

            var maximum = max_depth;
            if (maximum == null || value > maximum) {
                max_depth = value;
            }
        }
    }
}
