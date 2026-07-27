import Toybox.Activity;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

class max_depthView extends WatchUi.SimpleDataField {

    const feet_per_meter = 3.28084;
    const water_pressure = 9806.65; // pascal per meter

    var start_pressure;
    var max_depth = 0.0;

    var unit; // System.UNIT_METRIC or System.UNIT_STATUTE

    function initialize() {
        SimpleDataField.initialize();

        // Depth is a vertical distance in the environment, so it follows the
        // elevation unit setting rather than the (body) height setting.
        unit = System.getDeviceSettings().elevationUnits;

        // Set the label of the data field here. A SimpleDataField has no room
        // for a unit suffix on the value, so it goes in the label.
        label = (unit == System.UNIT_METRIC) ? "Max Depth (m)" : "Max Depth (ft)";
    }

    // The given info object contains all the current workout
    // information. Calculate a value and return it in this method.
    // Note that compute() and onUpdate() are asynchronous, and there is no
    // guarantee that compute() will be called before onUpdate().
    function compute(info as Activity.Info) as Numeric or Duration or String or Null {
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

        if (start_pressure == null) {
            start_pressure = current_pressure;
        }

        if (current_pressure == null || start_pressure == null) {
            return "n/a";
        }
        // Recalibrate if the watch seems to be out of water.
        if (start_pressure > current_pressure) {
            start_pressure = current_pressure;
        }

        var pressure_diff = current_pressure - start_pressure;
        var depth = pressure_diff/water_pressure;
        if (depth > max_depth) {
            max_depth = depth;
        }
        if (unit == System.UNIT_METRIC) {
            return max_depth.format("%.2f");
        } else {
            return (max_depth*feet_per_meter).format("%.1f");
        }
    }
}
