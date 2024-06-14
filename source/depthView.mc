import Toybox.Activity;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

class depthView extends WatchUi.SimpleDataField {

    private var start_pressure;
    private var unit; // System.UNIT_METRIC or System.UNIT_STATUTE

    function initialize() {
        SimpleDataField.initialize();
       
        unit = System.getDeviceSettings().heightUnits;

        // Set the label of the data field here.
        label = "Depth";
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
        var current_pressure = info.ambientPressure;
        if (start_pressure == null) {
            start_pressure = current_pressure;
        }

        var depthStr = "n/a";
        if (current_pressure != null && start_pressure != null) {
            var depth = (current_pressure - start_pressure)/1000.0;
            if (unit == System.UNIT_METRIC) {
                depthStr = depth.format("%.2f") + "m";
            } else {
                depthStr = (depth*3.28084).format("%1f") + "ft";
            }
        }
        return depthStr;
    }

}