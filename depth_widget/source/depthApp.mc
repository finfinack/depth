import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;
import DepthCore;

class depthApp extends Application.AppBase {

    // Held so a settings change can be pushed into the running views. The
    // glance builds its own model and picks settings up when it is created.
    private var _model as DepthModel?;

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
    // depthView is not built into the glance scope, so the type checker cannot
    // see it when checking this function for the glance. Only the widget scope
    // ever calls getInitialView(), so suppressing the glance check is correct.
    (:typecheck(disableGlanceCheck))
    function getInitialView() as [Views] or [Views, InputDelegates] {
        // The pages share one model so tracking continues whichever is shown.
        var model = new DepthModel();
        _model = model;
        return [ new depthView(model, PAGE_SUMMARY), new depthDelegate(model, PAGE_SUMMARY) ];
    }

    //! Settings can change while the widget is open, so apply them straight
    //! away rather than waiting for it to be reopened.
    function onSettingsChanged() as Void {
        var model = _model;
        if (model != null) {
            model.loadSettings();
            WatchUi.requestUpdate();
        }
    }

    (:glance)
    public function getGlanceView() as [ WatchUi.GlanceView ] or [ WatchUi.GlanceView, WatchUi.GlanceViewDelegate ] or Null {
        var view = new $.depthGlanceView();
        return [view] as [ WatchUi.GlanceView ];
    }
}

function getApp() as depthApp {
    return Application.getApp() as depthApp;
}
