import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;
import DepthCore;

//! The app's pages, in the order they are reached by paging down.
//!
//! The summary comes first because it answers the question the app is opened
//! for — how deep am I, and how deep have I been. Behind it is what the outing
//! adds up to: this one so far, then the last one, which only exists once there
//! has been a last one.
//!
//! There were separate full-screen Depth and Max Depth pages here. They were
//! dropped rather than kept: both showed a number the summary already shows,
//! and the summary shows it against the gauge ring, which is more than a bigger
//! font was buying.
enum {
    PAGE_SUMMARY = 0,
    PAGE_SESSION = 1,
    PAGE_LAST = 2
}

//! The pages that always exist. PAGE_LAST is not one of them: there is nothing
//! to put on it until a session has been stored, and an empty page in the loop
//! is worse than no page at all.
const PAGE_COUNT_BASE = 2;

//! How many pages the loop has, which depends on whether there is a last
//! session to show. Both the delegate's wrap-around and the page indicator have
//! to agree on this, so neither works it out for itself.
function pageCountFor(session as depthSession?) as Number {
    return (session == null) ? PAGE_COUNT_BASE : PAGE_COUNT_BASE + 1;
}

//! One page of the app: the live summary, this session's totals, or the last
//! session's.
//!
//! All pages share a DepthModel, so depth keeps being tracked whichever page is
//! on screen — including the dives and bottom time the session page shows.
class depthView extends WatchUi.View {

    private var _model as DepthModel;
    private var _page as Number;
    private var _session as depthSession?;
    private var _dataTimer as Timer.Timer?;
    private var _ring as depthRing;

    // Loaded once rather than in onUpdate(), which runs every second.
    private var _depthLabel as String;
    private var _maxLabel as String;
    private var _sessionLabel as String;
    private var _lastSessionLabel as String;
    private var _divesLabel as String;
    private var _bottomLabel as String;

    function initialize(model as DepthModel, page as Number, session as depthSession?) {
        View.initialize();

        _model = model;
        _page = page;
        _session = session;
        _ring = new depthRing(model);

        _depthLabel = WatchUi.loadResource(Rez.Strings.LabelDepth) as String;
        _maxLabel = WatchUi.loadResource(Rez.Strings.LabelMax) as String;

        // Only the two session pages use these, and only one page is ever on
        // screen — but a page switch builds a whole new view, so loading them
        // lazily would just move the same work to the same place.
        _sessionLabel = WatchUi.loadResource(Rez.Strings.LabelSession) as String;
        _lastSessionLabel = WatchUi.loadResource(Rez.Strings.LabelLastSession) as String;
        _divesLabel = WatchUi.loadResource(Rez.Strings.LabelDives) as String;
        _bottomLabel = WatchUi.loadResource(Rez.Strings.LabelBottomTime) as String;
    }

    // Called when this View is brought to the foreground. Restore
    // the state of this View and prepare it to be shown. This includes
    // loading resources into memory.
    function onShow() as Void {
        readSensor();

        // The pressure sensor updates about once per second, so polling
        // faster only costs battery. The timer is owned by the visible
        // view: started here and stopped again in onHide().
        if (_dataTimer == null) {
            _dataTimer = new Timer.Timer();
            _dataTimer.start(method(:updateDepth), 1000, true);
        }

        // Request a redraw when the app is shown
        WatchUi.requestUpdate();
    }

    // Update the view
    function onUpdate(dc as Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Before the readings, so a marker reaching inwards cannot land on top
        // of a number.
        //
        // Only the summary, which is the only page showing the current depth —
        // and the current depth is what the ring's arrowhead points at. The two
        // session pages are about totals, where nothing on the ring would refer
        // to what is being read.
        if (_page == PAGE_SUMMARY) {
            _ring.draw(dc, width, height);
        }

        // The summary carries both accent colours, so its page indicator stays
        // neutral rather than claiming one of them.
        var accent = Graphics.COLOR_WHITE;
        if (_page == PAGE_SUMMARY) {
            drawSummary(dc, width, height);
        } else if (_page == PAGE_SESSION) {
            accent = Graphics.COLOR_BLUE;
            drawSession(dc, width, height, accent);
        } else {
            accent = Graphics.COLOR_ORANGE;
            drawLastSession(dc, width, height, accent);
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
        readSensor();
        WatchUi.requestUpdate();
    }

    //! Feed the sensor to the model, and buzz if that reading crossed a colour
    //! band boundary on the way down.
    //!
    //! Every path that takes a reading goes through here, onShow() as well as
    //! the timer. A crossing is reported by the one update that saw it and
    //! cleared by the next, so a reading taken anywhere else would swallow it.
    private function readSensor() as Void {
        _model.update(Activity.getActivityInfo());

        if (_model.band_alerts) {
            alertBandCrossing(_model.band_crossed);
        }
    }

    //! The current depth, given the heading and the full-size number, with the
    //! session maximum under it in a smaller hand.
    //!
    //! The two are not equals. The depth is what the app is opened to read and
    //! what the ring around it refers to; the maximum is context. Giving them
    //! matching treatment, which is what this page used to do, made the reader
    //! work out which was which every time.
    private function drawSummary(dc as Dc, width as Number, height as Number) as Void {
        drawHeading(dc, width, height * 25 / 100, height * 32 / 100,
            _depthLabel, Graphics.COLOR_BLUE);

        drawValue(dc, width / 2, height * 45 / 100, _model.depth,
            Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_LARGE,
            true, _model.saturated);

        // A maximum only ever goes one way, so a trend on it would say nothing.
        // It is bounded by whether the sensor was ever pinned, not by whether
        // it is pinned now: the maximum outlives the moment it was reached.
        drawReading(dc, width, height * 63 / 100, height * 73 / 100,
            _maxLabel, Graphics.COLOR_ORANGE, _model.max_depth, false, _model.saturation_seen);
    }

    //! How this outing is going: dives so far and time under, both live.
    //!
    //! No maximum and no ring. The maximum is on the summary a page away, and
    //! the ring points at a current depth this page is not showing — the two
    //! numbers here are totals, which is a different question from how deep you
    //! are right now.
    private function drawSession(dc as Dc, width as Number, height as Number,
                                 accent as Graphics.ColorType) as Void {
        drawHeading(dc, width, height * 30 / 100, height * 37 / 100,
            _sessionLabel, accent);

        drawStat(dc, width, height * 50 / 100, Graphics.FONT_NUMBER_MILD, _divesLabel,
            _model.dive_count.format("%d"), Graphics.COLOR_WHITE);
        drawStat(dc, width, height * 66 / 100, Graphics.FONT_MEDIUM, _bottomLabel,
            formatDuration(_model.bottom_time), Graphics.COLOR_WHITE);
    }

    //! A page title with an accent rule under it, as every page but the summary
    //! of two readings used to have.
    private function drawHeading(dc as Dc, width as Number, labelY as Number, ruleY as Number,
                                 label as String, accent as Graphics.ColorType) as Void {
        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, labelY, Graphics.FONT_SMALL, label,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setPenWidth(2);
        dc.drawLine(width * 35 / 100, ruleY, width * 65 / 100, ruleY);
        dc.setPenWidth(1);
    }

    //! What the last outing came to: maximum depth, how many dives, and how
    //! long was spent under. Three numbers that are all finished, so nothing
    //! here is live and none of it carries a trend.
    //!
    //! The maximum is given the larger font because it is the one people go
    //! looking for; the other two are context around it.
    private function drawLastSession(dc as Dc, width as Number, height as Number,
                                     accent as Graphics.ColorType) as Void {
        var session = _session;
        if (session == null) {
            return; // Without one this page is not in the loop at all.
        }

        drawHeading(dc, width, height * 26 / 100, height * 33 / 100,
            _lastSessionLabel, accent);

        // Stored in meters and formatted here, so a session recorded before the
        // unit was changed still reads in the unit that is set now.
        drawStat(dc, width, height * 44 / 100, Graphics.FONT_MEDIUM, _maxLabel,
            _model.formatDepth(session.max_depth) + " " + _model.unitLabel(),
            DepthCore.depthColor(session.max_depth, _model.color_profile));
        drawStat(dc, width, height * 59 / 100, Graphics.FONT_SMALL, _divesLabel,
            session.dive_count.format("%d"), Graphics.COLOR_WHITE);
        drawStat(dc, width, height * 71 / 100, Graphics.FONT_SMALL, _bottomLabel,
            formatDuration(session.bottom_time), Graphics.COLOR_WHITE);
    }

    //! One "LABEL  value" line centred on the page, the label muted so the
    //! number carries the row. Centred as a pair rather than as two independent
    //! draws, so a long translation shifts the whole row instead of colliding
    //! with the value.
    private function drawStat(dc as Dc, width as Number, y as Number,
                              valueFont as Graphics.FontType, label as String,
                              value as String, color as Graphics.ColorType) as Void {
        var labelFont = Graphics.FONT_XTINY;
        var justify = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;

        var gap = dc.getTextWidthInPixels("  ", labelFont);
        var labelWidth = dc.getTextWidthInPixels(label, labelFont);
        var valueWidth = dc.getTextWidthInPixels(value, valueFont);
        var left = width / 2 - (labelWidth + gap + valueWidth) / 2;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left, y, labelFont, label, justify);

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + labelWidth + gap, y, valueFont, value, justify);
    }

    //! A small label with its reading underneath, for the summary page.
    private function drawReading(dc as Dc, width as Number, labelY as Number, valueY as Number,
                                 label as String, accent as Graphics.ColorType, value as Float?,
                                 withTrend as Boolean, limited as Boolean) as Void {
        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, labelY, Graphics.FONT_XTINY, label,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        drawValue(dc, width / 2, valueY, value,
            Graphics.FONT_NUMBER_MILD, Graphics.FONT_XTINY, Graphics.FONT_MEDIUM, withTrend, limited);
    }

    //! Draw the reading centred on (x, y): the trend indicator, then the number
    //! in a numeric font coloured by depth, then the unit in a smaller, muted
    //! font.
    private function drawValue(dc as Dc, x as Number, y as Number, value as Float?,
                               numberFont as Graphics.FontType, unitFont as Graphics.FontType,
                               fallbackFont as Graphics.FontType, withTrend as Boolean,
                               limited as Boolean) as Void {
        var text = _model.formatDepth(value);
        var color = DepthCore.readingColor(value, _model.color_profile, limited);

        if (value == null) {
            // The numeric fonts only contain digits, so "n/a" needs a text font.
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, fallbackFont, text,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        // ">=" cannot go through formatBounded() here: it would land in the
        // numeric font, which holds digits only. It gets its own draw in the
        // unit's text font, the same way the unit itself does.
        var boundText = ">=";
        // The "?" rides on the unit rather than the number, both because it
        // qualifies the whole reading and because the numeric fonts hold
        // digits only — the same reason ">=" is drawn separately below.
        var unitText = " " + _model.unitLabel() + _model.staleMark(value);
        var boundWidth = limited ? dc.getTextWidthInPixels(boundText, unitFont) : 0;
        var valueWidth = dc.getTextWidthInPixels(text, numberFont);
        var unitWidth = dc.getTextWidthInPixels(unitText, unitFont);

        // The indicator's slot is reserved whether or not a triangle goes in
        // it, so the reading does not shift sideways every time the trend
        // changes — a number that jitters is harder to read than one that does
        // not, and the trend changes far more often than the layout should.
        var trendSize = withTrend ? dc.getFontHeight(unitFont) / 2 : 0;
        var trendGap = trendSize / 2;

        var left = x - (trendSize + trendGap + boundWidth + valueWidth + unitWidth) / 2;
        if (withTrend) {
            drawTrend(dc, left + trendSize / 2, y, trendSize);
        }

        var valueX = left + trendSize + trendGap;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (limited) {
            dc.drawText(valueX, y, unitFont, boundText,
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            valueX += boundWidth;
        }
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
        var pages = pageCountFor(_session);
        var radius = 3;
        var spacing = radius * 4;
        var x = width / 2 - (spacing * (pages - 1)) / 2;

        for (var page = 0; page < pages; page += 1) {
            dc.setColor(page == _page ? accent : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x + page * spacing, y, radius);
        }
    }
}
