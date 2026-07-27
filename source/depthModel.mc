import Toybox.Activity;
import Toybox.Lang;
import Toybox.System;

//! Current and maximum depth derived from the pressure sensor.
//!
//! The widget pages and the glance view all read from an instance of this
//! class, so the pressure maths and the unit handling live in one place. The
//! maximum is tracked for as long as the instance lives, which means it covers
//! the current widget session and is not persisted across restarts.
(:glance)
class DepthModel {

    const feet_per_meter = 3.28084;
    const water_pressure = 9806.65; // pascal per meter

    //! Current depth in meters, or null while no pressure reading is available.
    var depth as Float?;
    //! Deepest reading in meters so far, or null before the first reading.
    var max_depth as Float?;

    var unit as System.UnitsSystem; // System.UNIT_METRIC or System.UNIT_STATUTE

    private var _start_pressure as Float?;

    function initialize() {
        // Depth is a vertical distance in the environment, so it follows the
        // elevation unit setting rather than the (body) height setting.
        unit = System.getDeviceSettings().elevationUnits;
    }

    //! Read the pressure sensor and update the current and the maximum depth.
    function update() as Void {
        var info = Activity.getActivityInfo();

        // See Activity.Info in the documentation for available information.
        // - altitude as Lang.Float or Null
        //   The altitude above mean sea level in meters (m).
        // - ambientPressure as Lang.Float or Null
        //   The ambient pressure in Pascals (Pa).
        // - rawAmbientPressure as Lang.Float or Null
        //   The raw ambient pressure in Pascals (Pa).
        // rawAmbientPressure is read straight from the sensor (temperature
        // compensated). ambientPressure is smoothed by a two-stage filter,
        // which lags during a fast descent, so it is only a fallback for
        // devices/contexts where the raw value is not populated.
        var current_pressure = info.rawAmbientPressure;
        if (current_pressure == null) {
            current_pressure = info.ambientPressure;
        }
        if (_start_pressure == null) {
            _start_pressure = current_pressure;
        }

        if (current_pressure == null || _start_pressure == null) {
            depth = null;
            return;
        }
        // Recalibrate if the watch seems to be out of water.
        if (_start_pressure > current_pressure) {
            _start_pressure = current_pressure;
        }

        var value = (current_pressure - _start_pressure) / water_pressure;
        depth = value;

        var max = max_depth;
        if (max == null || value > max) {
            max_depth = value;
        }
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
}
