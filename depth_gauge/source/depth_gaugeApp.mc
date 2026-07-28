import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! The barrel annotates DepthModel and depthColor() (:glance) for the widget's
//! sake. A data field has no glance — the compiler says so itself, with "Glance
//! applications are not supported for app type 'datafield'", and ignores the
//! annotation — but the editor's type checker builds a glance scope anyway and
//! then cannot find this app's view class in it.
//!
//! Suppressing the check on the whole class is correct rather than convenient:
//! there is no glance scope here for it to be right about. It goes on the class
//! because the view is named in a member variable as well as in two methods.
(:typecheck(disableGlanceCheck))
class depth_gaugeApp extends Application.AppBase {

    // Held so a settings change can be pushed into the running field.
    private var _view as depth_gaugeView?;

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
    }

    // Return the initial view of your application here
    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new depth_gaugeView();
        _view = view;
        return [ view ];
    }

    //! Settings can change while the field is on screen, so push them through
    //! rather than waiting for the next activity.
    function onSettingsChanged() as Void {
        var view = _view;
        if (view != null) {
            view.onSettingsChanged();
        }
    }

}

function getApp() as depth_gaugeApp {
    return Application.getApp() as depth_gaugeApp;
}
