import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class depthApp extends Application.AppBase {

    // Held so a settings change can be pushed into the running field.
    private var _view as depthView?;

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
    }

    // Return the initial view of your application here.
    //
    // The barrel annotates DepthModel and depthColor() (:glance) for the
    // widget's sake. A data field has no glance — the compiler says so itself,
    // with "Glance applications are not supported for app type 'datafield'",
    // and ignores the annotation — but the editor's type checker builds a
    // glance scope anyway and then cannot see depthView in it. Suppressing the
    // check is correct rather than convenient: there is no scope here for it to
    // be wrong about.
    (:typecheck(disableGlanceCheck))
    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new depthView();
        _view = view;
        return [ view ];
    }

    //! Settings can change while the field is on screen, so push them through
    //! rather than waiting for the next activity.
    (:typecheck(disableGlanceCheck))
    function onSettingsChanged() as Void {
        var view = _view;
        if (view != null) {
            view.onSettingsChanged();
        }
    }

}

function getApp() as depthApp {
    return Application.getApp() as depthApp;
}