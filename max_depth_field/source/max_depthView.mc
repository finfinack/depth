import Toybox.Activity;
import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;
import DepthCore;

class max_depthView extends WatchUi.SimpleDataField {

    //! Field numbers for this app's FIT contributions. They only have to be
    //! unique within the app, since the FIT file scopes them by developer id.
    enum FieldId {
        FIELD_MAX_DEPTH = 0,
        FIELD_MAX_DEPTH_RAW = 1
    }

    private var _model as DepthModel;

    // Only the session summary. The per-record depth series belongs to the
    // Depth field; recording it here as well would duplicate the whole graph
    // for anyone running both fields in the same activity.
    private var _maxDepthField as FitContributor.Field;

    // The same maximum with no spike rejection at all, so the true deepest
    // point of the session is bracketed between the two. It matters more here
    // than in the Depth field: that one records the whole depth series, so a
    // raw maximum could be recovered from it, and this one records nothing
    // else at all.
    private var _maxDepthRawField as FitContributor.Field;

    function initialize() {
        SimpleDataField.initialize();

        _model = new DepthModel(DepthCore.REZERO_HANDLE);
        updateLabel();

        // Always recorded in centimeters, whatever the display unit is set to.
        // The unit setting can be changed part way through an activity, and a
        // field whose meaning changed halfway would be worse than useless.
        _maxDepthField = createField("max_depth", FIELD_MAX_DEPTH, FitContributor.DATA_TYPE_UINT16,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "cm" });
        _maxDepthRawField = createField("max_depth_raw", FIELD_MAX_DEPTH_RAW,
            FitContributor.DATA_TYPE_UINT16,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "cm" });

        // The fields need a value before the first compute(), or an activity
        // saved without ever getting a pressure reading records nothing at all.
        _maxDepthField.setData(0);
        _maxDepthRawField.setData(0);
    }

    //! A SimpleDataField has no room for a unit suffix on the value, so the unit
    //! goes in the label — which means the label has to follow the unit setting.
    //!
    //! The unit is appended rather than being part of the translated string, so
    //! a translation is one short phrase and cannot get the symbols wrong; "m"
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

        _maxDepthField.setData(DepthCore.depthCentimeters(_model.max_depth));
        _maxDepthRawField.setData(DepthCore.depthCentimeters(_model.max_depth_raw));

        // ">=" in front once the sensor has looked pinned at any point: a
        // maximum reached while the reading was at its ceiling is the ceiling,
        // not the dive.
        return _model.formatBounded(_model.max_depth, _model.saturation_seen)
            + _model.staleMark(_model.max_depth);
    }
}
