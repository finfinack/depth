import Toybox.WatchUi;
import Toybox.Lang;
import Toybox.Application.Storage;

(:glance)
class depthGlanceView extends WatchUi.GlanceView
{
    const feet_per_meter = 3.28084;
    const water_pressure = 9806.65; // pascal per meter

    var start_pressure;
    var depth = "n/a";

    var unit; // System.UNIT_METRIC or System.UNIT_STATUTE

    function initialize() {
        GlanceView.initialize();

        // Depth is a vertical distance in the environment, so it follows the
        // elevation unit setting rather than the (body) height setting.
        unit = System.getDeviceSettings().elevationUnits;
    }

    function onUpdate(dc) {
        self.updateDepth();

        var valueFont = Graphics.FONT_TINY;

        var width = dc.getWidth();
        var height = dc.getHeight();

        var depthY = height / 2;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.drawText(width / 2, depthY, valueFont, depth, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function onStop() {
    }

    //! On a timer interval, read the pressure sensor and update the depth.
    function updateDepth() as Void {
        var info = Activity.getActivityInfo();
        if (info == null) {
            depth = "n/a";
            return;
        }

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
            depth = "n/a";
            return;
        }
        // Recalibrate if the watch seems to be out of water.
        if (start_pressure > current_pressure) {
            start_pressure = current_pressure;
        }

        var pressure_diff = current_pressure - start_pressure;
        var depth_value = pressure_diff/water_pressure;
        if (unit == System.UNIT_METRIC) {
            depth = "Depth: " + depth_value.format("%.2f") + "m";
        } else {
            depth = "Depth: " + (depth_value*feet_per_meter).format("%.1f") + "ft";
        }
    }
}
