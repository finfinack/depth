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

    //! Ignore the touchscreen while the app is open.
    //!
    //! Under water the screen fires by itself: water pressure reads as a tap
    //! and water moving across the glass reads as a swipe. On every touch
    //! device in the product list a tap is the Select behaviour and a swipe is
    //! a page change or Back, so the water can open the re-zero confirmation,
    //! page the app, or close it — and it does so exactly when none of it can
    //! be checked or undone.
    //!
    //! Consuming the raw events costs nothing here. Returning true stops them
    //! being mapped to a behaviour at all, and every device this ships to has
    //! physical buttons for the same three behaviours, so the app is driven by
    //! buttons and by nothing else.
    //!
    //! It is not a complete guard against being closed by the water: some
    //! devices deliver a swipe right as a KEY_ESC rather than as a swipe, and
    //! that arrives at onBack() below without passing through here. Blocking
    //! onBack() as well would take away the only way out of the app, so it is
    //! deliberately left alone.
    function onTap(event as WatchUi.ClickEvent) as Boolean {
        return true;
    }

    function onSwipe(event as WatchUi.SwipeEvent) as Boolean {
        return true;
    }

    function onHold(event as WatchUi.ClickEvent) as Boolean {
        return true;
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
