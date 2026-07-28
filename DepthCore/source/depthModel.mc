import Toybox.Activity;
import Toybox.Application;
import Toybox.Lang;
import Toybox.System;

module DepthCore {

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
    //!   cannot drag the baseline down with it. If that state lasts implausibly
    //!   long the baseline itself is the most likely culprit, so a watchdog
    //!   starts over from the current pressure — otherwise a bad sample that
    //!   made the watch look permanently submerged would have no way out.
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

        // How long the watch may look submerged before the baseline is assumed to
        // be wrong rather than the depth being real.
        const max_submerged = 600000; // ms

        // Fastest descent treated as a real one. Anything quicker is a sensor
        // glitch, and must not be allowed to reach the maximum.
        const max_descent_rate = 3.0; // m/s

        //! Current depth in meters, or null while no pressure reading is available.
        var depth as Float?;
        //! Deepest reading in meters so far, or null before the first reading.
        var max_depth as Float?;

        var unit as System.UnitsSystem = System.UNIT_METRIC; // or System.UNIT_STATUTE
        var water_pressure as Float = fresh_water_pressure;

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

        function initialize() {
            loadSettings();
        }

        //! Read the app settings. Called once at startup and again whenever the app
        //! is told they changed, so the long-lived widget and glance pick a change
        //! up without being restarted.
        function loadSettings() as Void {
            water_pressure = (numberSetting("waterType", WATER_FRESH) == WATER_SALT)
                ? salt_water_pressure
                : fresh_water_pressure;

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
            if (pressure == null) {
                depth = null;
                return;
            }

            var now = System.getTimer();
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
            var previous_pressure = _previous_pressure;
            var confirmed = (previous_pressure != null && previous_pressure > pressure)
                ? previous_pressure
                : pressure;
            _previous_pressure = pressure;

            if (pressure - baseline <= surface_band) {
                // At the surface: the window tracks the surface pressure.
                _submerged_since = null;
                feedWindow(confirmed, now);
                baseline = windowMinimum(confirmed);
                _baseline = baseline;
            } else {
                // Submerged: the window is frozen, so the dive cannot pull the
                // baseline down after it.
                var since = _submerged_since;
                if (since == null) {
                    _submerged_since = now;
                } else if (now - since > max_submerged || now < since) {
                    rebaseline(pressure, now);
                    baseline = pressure;
                }
            }

            var value = (pressure - baseline) / water_pressure;
            if (value < 0.0) {
                value = 0.0;
            }
            depth = value;
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
            _previous_depth = null;
            _previous_pressure = null;
            depth = null;
            max_depth = null;
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

        //! The unit suffix matching formatDepth().
        function unitLabel() as String {
            return (unit == System.UNIT_METRIC) ? "m" : "ft";
        }

        //! Read a numeric setting, falling back if it is missing or the wrong type.
        private function numberSetting(key as String, fallback as Number) as Number {
            var value = Properties.getValue(key);
            if (value instanceof Lang.Number) {
                return value;
            }
            return fallback;
        }

        //! Read a boolean setting, falling back if it is missing or the wrong type.
        private function booleanSetting(key as String, fallback as Boolean) as Boolean {
            var value = Properties.getValue(key);
            if (value instanceof Lang.Boolean) {
                return value;
            }
            return fallback;
        }

        //! Start the baseline over from a single sample.
        private function rebaseline(pressure as Float, now as Number) as Void {
            _baseline = pressure;
            _min_current = pressure;
            _min_previous = null;
            _bucket_start = now;
            _submerged_since = null;
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

        //! Track the deepest reading, guarded against noise.
        private function updateMaximum(value as Float, now as Number) as Void {
            var previous = _previous_depth;
            var previous_time = _previous_time;
            _previous_depth = value;
            _previous_time = now;

            if (previous == null) {
                return; // A maximum needs two samples to confirm it.
            }

            var seconds = (now - previous_time) / 1000.0;
            if (seconds <= 0.0 || (value - previous) > max_descent_rate * seconds) {
                return; // Faster than any real descent, so treat it as a glitch.
            }

            // A new maximum has to be supported by two consecutive samples, so a
            // single noisy spike cannot latch into it permanently.
            var confirmed = (value < previous) ? value : previous;
            var maximum = max_depth;
            if (maximum == null || confirmed > maximum) {
                max_depth = confirmed;
            }
        }
    }
}
