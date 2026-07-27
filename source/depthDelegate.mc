import Toybox.Lang;
import Toybox.WatchUi;

//! Pages through the widget with swipe/press up and down, the way the built-in
//! widgets do. The pages wrap around, so either direction toggles between the
//! current and the maximum depth.
class depthDelegate extends WatchUi.BehaviorDelegate {

    private var _model as DepthModel;
    private var _page as Number;

    function initialize(model as DepthModel, page as Number) {
        BehaviorDelegate.initialize();

        _model = model;
        _page = page;
    }

    function onNextPage() as Boolean {
        showPage((_page + 1) % PAGE_COUNT, WatchUi.SLIDE_UP);
        return true;
    }

    function onPreviousPage() as Boolean {
        showPage((_page + PAGE_COUNT - 1) % PAGE_COUNT, WatchUi.SLIDE_DOWN);
        return true;
    }

    //! Replace the current page. The model is handed on so the depth history
    //! survives the switch.
    private function showPage(page as Number, transition as WatchUi.SlideType) as Void {
        WatchUi.switchToView(new depthView(_model, page), new depthDelegate(_model, page), transition);
    }
}
