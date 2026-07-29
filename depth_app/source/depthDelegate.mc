import Toybox.Lang;
import Toybox.WatchUi;
import DepthCore;

//! Pages through the app with swipe/press up and down, the way the built-in
//! ones do. The pages wrap around, so either direction toggles between the
//! current and the maximum depth.
class depthDelegate extends WatchUi.BehaviorDelegate {

    private var _model as DepthModel;
    private var _page as Number;
    private var _session as depthSession?;

    function initialize(model as DepthModel, page as Number, session as depthSession?) {
        BehaviorDelegate.initialize();

        _model = model;
        _page = page;
        _session = session;
    }

    function onNextPage() as Boolean {
        var pages = pageCountFor(_session);
        showPage((_page + 1) % pages, WatchUi.SLIDE_UP);
        return true;
    }

    function onPreviousPage() as Boolean {
        var pages = pageCountFor(_session);
        showPage((_page + pages - 1) % pages, WatchUi.SLIDE_DOWN);
        return true;
    }

    //! Offer to re-zero, which is needed when the app was opened while
    //! already in the water or at a different altitude. It is behind a
    //! confirmation because it also drops the maximum, which cannot be
    //! recovered.
    function onSelect() as Boolean {
        WatchUi.pushView(
            new WatchUi.Confirmation(WatchUi.loadResource(Rez.Strings.RezeroConfirm) as String),
            new rezeroDelegate(_model),
            WatchUi.SLIDE_UP);
        return true;
    }

    //! Replace the current page. The model is handed on so the depth history
    //! survives the switch.
    private function showPage(page as Number, transition as WatchUi.SlideType) as Void {
        WatchUi.switchToView(new depthView(_model, page, _session),
            new depthDelegate(_model, page, _session), transition);
    }
}

//! Applies the re-zero once it has been confirmed.
class rezeroDelegate extends WatchUi.ConfirmationDelegate {

    private var _model as DepthModel;

    function initialize(model as DepthModel) {
        ConfirmationDelegate.initialize();

        _model = model;
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            _model.rezero();
            WatchUi.requestUpdate();
        }
        return true;
    }
}
