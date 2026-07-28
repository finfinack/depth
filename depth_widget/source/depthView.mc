import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;
import DepthCore;

//! The widget pages, in the order they are reached by paging down. The summary
//! comes first so opening the widget answers both questions at once, with the
//! single-value pages behind it for a bigger read-out.
enum {
    PAGE_SUMMARY = 0,
    PAGE_CURRENT = 1,
    PAGE_MAX = 2
}
const PAGE_COUNT = 3;

//! One page of the widget: both readings, the current depth, or the maximum.
//!
//! All pages share a DepthModel, so the maximum keeps being tracked whichever
//! page is on screen.
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

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // The summary carries both accent colours, so its page indicator stays
        // neutral rather than claiming one of them.
        var accent = Graphics.COLOR_WHITE;
        if (_page == PAGE_SUMMARY) {
            drawSummary(dc, width, height);
        } else {
            accent = (_page == PAGE_MAX) ? Graphics.COLOR_ORANGE : Graphics.COLOR_BLUE;
            drawSingle(dc, width, height, accent);
        }

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

    //! Both readings stacked. The labels drop to the smallest font and lose the
    //! "DEPTH" suffix on the maximum, which leaves room for two numbers without
    //! either of them crowding the other; the accent colours do most of the work
    //! of telling the two apart.
    private function drawSummary(dc as Dc, width as Number, height as Number) as Void {
        drawReading(dc, width, height * 28 / 100, height * 40 / 100,
            "DEPTH", Graphics.COLOR_BLUE, _model.depth, true);
        // A maximum only ever goes one way, so a trend on it would say nothing.
        drawReading(dc, width, height * 57 / 100, height * 69 / 100,
            "MAX", Graphics.COLOR_ORANGE, _model.max_depth, false);
    }

    //! A single reading filling the page, with an accent rule under the label.
    private function drawSingle(dc as Dc, width as Number, height as Number, accent as Graphics.ColorType) as Void {
        var isMax = (_page == PAGE_MAX);
        var value = _model.depth;
        if (isMax) {
            value = _model.max_depth;
        }

        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 3 / 10, Graphics.FONT_SMALL, isMax ? "MAX DEPTH" : "DEPTH",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Accent rule between the label and the value.
        var ruleY = height * 38 / 100;
        dc.setPenWidth(2);
        dc.drawLine(width * 35 / 100, ruleY, width * 65 / 100, ruleY);

        drawValue(dc, width / 2, height / 2, value,
            Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_LARGE, !isMax);
    }

    //! A small label with its reading underneath, for the summary page.
    private function drawReading(dc as Dc, width as Number, labelY as Number, valueY as Number,
                                 label as String, accent as Graphics.ColorType, value as Float?,
                                 withTrend as Boolean) as Void {
        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, labelY, Graphics.FONT_XTINY, label,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        drawValue(dc, width / 2, valueY, value,
            Graphics.FONT_NUMBER_MILD, Graphics.FONT_XTINY, Graphics.FONT_MEDIUM, withTrend);
    }

    //! Draw the reading centred on (x, y): the trend indicator, then the number
    //! in a numeric font coloured by depth, then the unit in a smaller, muted
    //! font.
    private function drawValue(dc as Dc, x as Number, y as Number, value as Float?,
                               numberFont as Graphics.FontType, unitFont as Graphics.FontType,
                               fallbackFont as Graphics.FontType, withTrend as Boolean) as Void {
        var text = _model.formatDepth(value);

        if (value == null) {
            // The numeric fonts only contain digits, so "n/a" needs a text font.
            dc.setColor(DepthCore.depthColor(value), Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, fallbackFont, text,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var unitText = " " + _model.unitLabel();
        var valueWidth = dc.getTextWidthInPixels(text, numberFont);
        var unitWidth = dc.getTextWidthInPixels(unitText, unitFont);

        // The indicator's slot is reserved whether or not a triangle goes in
        // it, so the reading does not shift sideways every time the trend
        // changes — a number that jitters is harder to read than one that does
        // not, and the trend changes far more often than the layout should.
        var trendSize = withTrend ? dc.getFontHeight(unitFont) / 2 : 0;
        var trendGap = trendSize / 2;

        var left = x - (trendSize + trendGap + valueWidth + unitWidth) / 2;
        if (withTrend) {
            drawTrend(dc, left + trendSize / 2, y, trendSize);
        }

        var valueX = left + trendSize + trendGap;
        dc.setColor(DepthCore.depthColor(value), Graphics.COLOR_TRANSPARENT);
        dc.drawText(valueX, y, numberFont, text,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(valueX + valueWidth, y, unitFont, unitText,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! A triangle centred on (x, y) pointing the way the depth is going: red and
    //! down while descending, blue and up while ascending, nothing at all while
    //! level.
    //!
    //! Red for deeper and blue for shallower matches the depth colour scale,
    //! which already runs blue at the surface to red at the bottom. Drawn as a
    //! polygon rather than an arrow character because the built-in fonts have
    //! patchy glyph coverage and would show empty boxes on some devices.
    private function drawTrend(dc as Dc, x as Number, y as Number, size as Number) as Void {
        var trend = _model.trend;
        if (trend == DepthCore.TREND_LEVEL) {
            return;
        }

        var half = size / 2;
        if (trend == DepthCore.TREND_DESCENDING) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[x - half, y - half], [x + half, y - half], [x, y + half]] as Array<Graphics.Point2D>);
        } else {
            dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[x - half, y + half], [x + half, y + half], [x, y - half]] as Array<Graphics.Point2D>);
        }
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
