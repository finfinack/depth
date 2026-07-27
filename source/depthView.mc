import Toybox.Activity;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

class depthView extends WatchUi.SimpleDataField {

    private var _model as DepthModel;

    function initialize() {
        SimpleDataField.initialize();

        _model = new DepthModel();
        updateLabel();
    }

    //! A SimpleDataField has no room for a unit suffix on the value, so the unit
    //! goes in the label — which means the label has to follow the unit setting.
    function updateLabel() as Void {
        label = (_model.unit == System.UNIT_METRIC) ? "Depth (m)" : "Depth (ft)";
    }

    //! Called by the app when the user changes a setting.
    function onSettingsChanged() as Void {
        _model.loadSettings();
        updateLabel();
    }

    // The given info object contains all the current workout
    // information. Calculate a value and return it in this method.
    // Note that compute() and onUpdate() are asynchronous, and there is no
    // guarantee that compute() will be called before onUpdate().
    function compute(info as Activity.Info) as Numeric or Duration or String or Null {
        _model.update(info);
        return _model.formatDepth(_model.depth);
    }

}