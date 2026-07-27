import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! The widget pages, in the order they are reached by paging down.
enum {
    PAGE_CURRENT = 0,
    PAGE_MAX = 1
}
const PAGE_COUNT = 2;

//! One page of the widget: either the current or the maximum depth.
//!
//! Both pages share a DepthModel, so the maximum keeps being tracked while the
//! current depth page is on screen and vice versa.
class depthView extends WatchUi.View {

    private var _model as DepthModel;
    private var _page as Number;
    private var _dataTimer as Timer.Timer?;

    function initialize(model as DepthModel, page as Number) {
        View.initialize();

        _model = model;
        _page = page;
    }

    // Called when this View is brought to the foreground. Restore
    // the state of this View and prepare it to be shown. This includes
    // loading resources into memory.
    function onShow() as Void {
        _model.update(Activity.getActivityInfo());

        // The pressure sensor updates about once per second, so polling
        // faster only costs battery. The timer is owned by the visible
        // view: started here and stopped again in onHide().
        if (_dataTimer == null) {
            _dataTimer = new Timer.Timer();
            _dataTimer.start(method(:updateDepth), 1000, true);
        }

        // Request a redraw when the widget is shown
        WatchUi.requestUpdate();
    }

    // Update the view
    function onUpdate(dc as Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();

        var isMax = (_page == PAGE_MAX);
        var label = isMax ? "MAX DEPTH" : "DEPTH";
        var accent = isMax ? Graphics.COLOR_ORANGE : Graphics.COLOR_BLUE;
        var value = _model.depth;
        if (isMax) {
            value = _model.max_depth;
        }

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var labelY = height * 3 / 10;
        var valueY = height / 2;

        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, labelY, Graphics.FONT_SMALL, label,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Accent rule between the label and the value.
        var ruleY = height * 38 / 100;
        dc.setPenWidth(2);
        dc.drawLine(width * 35 / 100, ruleY, width * 65 / 100, ruleY);

        drawValue(dc, width / 2, valueY, value);
        drawPageIndicator(dc, width, height * 82 / 100, accent);
    }

    // Called when this View is removed from the screen. Save the
    // state of this View here. This includes freeing resources from
    // memory.
    function onHide() as Void {
        if (_dataTimer != null) {
            _dataTimer.stop();
            _dataTimer = null;
        }
    }

    //! On a timer interval, read the pressure sensor and update the depth.
    function updateDepth() as Void {
        _model.update(Activity.getActivityInfo());
        WatchUi.requestUpdate();
    }

    //! Draw the reading centred on (x, y): the number in a large numeric font
    //! coloured by depth, followed by the unit in a smaller, muted font.
    private function drawValue(dc as Dc, x as Number, y as Number, value as Float?) as Void {
        var text = _model.formatDepth(value);

        if (value == null) {
            // The numeric fonts only contain digits, so "n/a" needs a text font.
            dc.setColor(depthColor(value), Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, Graphics.FONT_LARGE, text,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var unitText = " " + _model.unitLabel();
        var valueWidth = dc.getTextWidthInPixels(text, Graphics.FONT_NUMBER_MEDIUM);
        var unitWidth = dc.getTextWidthInPixels(unitText, Graphics.FONT_SMALL);
        var valueX = x - (valueWidth + unitWidth) / 2;

        dc.setColor(depthColor(value), Graphics.COLOR_TRANSPARENT);
        dc.drawText(valueX, y, Graphics.FONT_NUMBER_MEDIUM, text,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(valueX + valueWidth, y, Graphics.FONT_SMALL, unitText,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! One dot per page, the current one highlighted in the page accent colour.
    private function drawPageIndicator(dc as Dc, width as Number, y as Number, accent as Graphics.ColorType) as Void {
        var radius = 3;
        var spacing = radius * 4;
        var x = width / 2 - (spacing * (PAGE_COUNT - 1)) / 2;

        for (var page = 0; page < PAGE_COUNT; page += 1) {
            dc.setColor(page == _page ? accent : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x + page * spacing, y, radius);
        }
    }
}
