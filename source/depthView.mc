import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Activity;
import Toybox.Timer;

class depthView extends WatchUi.View {

    const depth_label = "Depth";
    // const max_depth_label = "Max Depth";

    const feet_per_meter = 3.28084;
    const water_pressure = 9806.65; // pascal per meter

    var start_pressure;
    var depth = "n/a";
    // private var max_depth = "n/a";
    // private var max_depth_value = 0.0;

    var unit; // System.UNIT_METRIC or System.UNIT_STATUTE

    private var _dataTimer as Timer.Timer?;

    function initialize() {
        View.initialize();

        // Depth is a vertical distance in the environment, so it follows the
        // elevation unit setting rather than the (body) height setting.
        unit = System.getDeviceSettings().elevationUnits;
    }

    // Load your resources here
    function onLayout(dc as Dc) as Void {
        setLayout(Rez.Layouts.MainLayout(dc));
    }

    // Called when this View is brought to the foreground. Restore
    // the state of this View and prepare it to be shown. This includes
    // loading resources into memory.
    function onShow() as Void {
        self.updateDepth();

        // The pressure sensor updates about once per second, so polling
        // faster only costs battery. The timer is owned by the visible
        // view: started here and stopped again in onHide().
        if (_dataTimer == null) {
            _dataTimer = new Timer.Timer();
            _dataTimer.start(method(:updateDepth), 1000, true);
        }

        // Request a redraw when the widget is shown
        WatchUi.requestUpdate();
    }

    // Update the view
    function onUpdate(dc as Dc) as Void {
        // Call the parent onUpdate function to redraw the layout
        // View.onUpdate(dc);

        // self.updateDepth();

        var labelFont = Graphics.FONT_SMALL;
        var valueFont = Graphics.FONT_LARGE;

        var width = dc.getWidth();
        var height = dc.getHeight();

        var labelDepthY = height / 4;
        var depthY = (height / 4) * 2;
        // var labelDepthY = height / 7;
        // var depthY = (height / 7) * 2;
        // var labelMaxDepthY = (height / 7) * 4;
        // var maxDepthY = (height / 7) * 5;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        dc.drawText(width / 2, labelDepthY, labelFont, depth_label, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(width / 2, depthY, valueFont, depth, Graphics.TEXT_JUSTIFY_CENTER);
        // dc.drawText(width / 2, labelMaxDepthY, labelFont, max_depth_label, Graphics.TEXT_JUSTIFY_CENTER);
        // dc.drawText(width / 2, maxDepthY, valueFont, max_depth, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Called when this View is removed from the screen. Save the
    // state of this View here. This includes freeing resources from
    // memory.
    function onHide() as Void {
        if (_dataTimer != null) {
            _dataTimer.stop();
            _dataTimer = null;
        }
    }

    //! On a timer interval, read the pressure sensor and update the depth.
    function updateDepth() as Void {
        var info = Activity.getActivityInfo();
        if (info == null) {
            depth = "n/a";
            // max_depth = "n/a";
            WatchUi.requestUpdate();
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
            // max_depth = "n/a";

            WatchUi.requestUpdate();
            return;
        }
        // Recalibrate if the watch seems to be out of water.
        if (start_pressure > current_pressure) {
            start_pressure = current_pressure;
        }

        var pressure_diff = current_pressure - start_pressure;
        var depth_value = pressure_diff/water_pressure;
        if (unit == System.UNIT_METRIC) {
            depth = depth_value.format("%.2f") + "m";
        } else {
            depth = (depth_value*feet_per_meter).format("%.1f") + "ft";
        }

        // if (depth_value > max_depth_value) {
        //     max_depth_value = depth_value;
        // }
        // if (unit == System.UNIT_METRIC) {
        //     max_depth = max_depth_value.format("%.2f") + "m";
        // } else {
        //     max_depth = (max_depth_value*feet_per_meter).format("%1f") + "ft";
        // }

        WatchUi.requestUpdate();
    }

}
