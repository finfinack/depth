import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class max_depthApp extends Application.AppBase {

    // Held so a settings change can be pushed into the running field.
    private var _view as max_depthView?;

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
        var view = new max_depthView();
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

function getApp() as max_depthApp {
    return Application.getApp() as max_depthApp;
}