import Toybox.Activity;
import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;
import DepthCore;

class depthView extends WatchUi.SimpleDataField {

    //! Field numbers for this app's FIT contributions. They only have to be
    //! unique within the app, since the FIT file scopes them by developer id.
    enum FieldId {
        FIELD_DEPTH = 0,
        FIELD_MAX_DEPTH = 1,
        FIELD_PRESSURE = 2
    }

    private var _model as DepthModel;

    // The depth of every record, which is what makes a graph in Garmin Connect,
    // and the deepest reading of the session as a single summary value.
    private var _depthField as FitContributor.Field;
    private var _maxDepthField as FitContributor.Field;

    // The sensor reading the depth was derived from, before anything is done to
    // it. Depth is only as good as the surface baseline the app had to guess
    // at, and a guess cannot be checked against its own output — so the input
    // is recorded alongside it.
    private var _pressureField as FitContributor.Field;

    function initialize() {
        SimpleDataField.initialize();

        _model = new DepthModel();
        updateLabel();

        // Always recorded in centimeters, whatever the display unit is set to.
        // The unit setting can be changed part way through an activity, and a
        // field whose meaning changed halfway would be worse than useless.
        _depthField = createField("depth", FIELD_DEPTH, FitContributor.DATA_TYPE_UINT16,
            { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "cm" });
        _maxDepthField = createField("max_depth", FIELD_MAX_DEPTH, FitContributor.DATA_TYPE_UINT16,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "cm" });

        // Whole pascal in a UINT32. Ambient pressure is around 100000 Pa, which
        // does not fit a UINT16 at any useful resolution.
        _pressureField = createField("pressure", FIELD_PRESSURE, FitContributor.DATA_TYPE_UINT32,
            { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "Pa" });

        // Every field needs a value before the first compute(), or an activity
        // that is saved without ever getting a pressure reading records nothing.
        _depthField.setData(0);
        _maxDepthField.setData(0);
        _pressureField.setData(0);
    }

    //! A SimpleDataField has no room for a unit suffix on the value, so the unit
    //! goes in the label — which means the label has to follow the unit setting.
    //!
    //! The unit is appended rather than being part of the translated string, so
    //! a translation is one short word and cannot get the symbols wrong; "m"
    //! and "ft" are the same in every language this could ship in.
    function updateLabel() as Void {
        var text = WatchUi.loadResource(Rez.Strings.FieldLabel) as String;
        label = text + " (" + _model.unitLabel() + ")";
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

        _depthField.setData(DepthCore.depthCentimeters(_model.depth));
        _maxDepthField.setData(DepthCore.depthCentimeters(_model.max_depth));
        _pressureField.setData(DepthCore.pressurePascals(_model.pressure));

        // ">=" in front once the sensor looks pinned: past its ceiling the
        // reading stops rising however deep the diver goes, and this field has
        // no colour of its own to say so.
        return _model.formatBounded(_model.depth, _model.saturated);
    }

}
