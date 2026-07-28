import Toybox.Activity;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import DepthCore;

//! Depth drawn two ways: a chart of the last couple of minutes, or a gauge of
//! where the current reading sits in the colour range.
//!
//! The other two fields are SimpleDataFields: they hand a string to the system
//! and the system draws it. That is all a SimpleDataField can do, so anything
//! with a shape has to be a full DataField, which gets an onUpdate(dc) and the
//! whole area to itself — and with it the job of drawing the label, picking a
//! font that fits, and honouring the day/night background the system chose.
//!
//! This one records nothing. The per-record depth series and the raw pressure
//! belong to the Depth field and the session maximum to the Max Depth field;
//! writing them here as well would duplicate the whole graph in Garmin Connect
//! for anyone running two of these at once. Pair it with the Depth field if the
//! activity should carry the data as well as show it.
class depth_graphView extends WatchUi.DataField {

    // Values of the fieldStyle setting.
    const STYLE_CHART = 0;
    const STYLE_GAUGE = 1;

    // Two minutes at the one sample per second compute() is called at: long
    // enough to hold several breath-hold dives, short enough that the trace is
    // still legible across a quarter-screen field.
    const history_samples = 120;

    // "No reading", which is not the same as 0 cm — that is the surface.
    const no_reading = -1;

    // Depths the chart snaps its bottom edge to, in centimeters. Fixed steps
    // rather than a continuous fit to the deepest sample, so the trace holds
    // still instead of creeping up the field every time the maximum gains a
    // centimeter.
    const scale_steps = [200, 500, 1000, 2000, 3000, 5000, 10000] as Array<Number>;

    private var _model as DepthModel;
    private var _label as String;
    private var _style as Number = STYLE_CHART;

    // Depth history in centimeters, as a ring buffer. Centimeters in a Number
    // rather than metres in a Float: the resolution the FIT file already
    // records at, and the chart is drawn in whole pixels anyway.
    private var _history as Array<Number>;
    private var _next as Number = 0;
    private var _filled as Number = 0;

    function initialize() {
        DataField.initialize();

        _model = new DepthModel();
        _label = WatchUi.loadResource(Rez.Strings.FieldLabel) as String;
        _style = styleSetting();

        _history = new [history_samples] as Array<Number>;
        for (var i = 0; i < history_samples; i += 1) {
            _history[i] = no_reading;
        }
    }

    //! Called by the app when the user changes a setting.
    function onSettingsChanged() as Void {
        _model.loadSettings();
        _style = styleSetting();
    }

    //! Read the sensor and add a sample. Called about once a second.
    function compute(info as Activity.Info) as Void {
        _model.update(info);

        var depth = _model.depth;
        _history[_next] = (depth == null) ? no_reading : DepthCore.depthCentimeters(depth);
        _next = (_next + 1) % history_samples;
        if (_filled < history_samples) {
            _filled += 1;
        }
    }

    function onUpdate(dc as Dc) as Void {
        // The system picks the background: white in day mode, black at night,
        // and a field that ignores it is unreadable in one of the two.
        var background = getBackgroundColor();
        var foreground = (background == Graphics.COLOR_WHITE)
            ? Graphics.COLOR_BLACK
            : Graphics.COLOR_WHITE;

        dc.setColor(background, background);
        dc.clear();

        var width = dc.getWidth();
        var height = dc.getHeight();

        // Label on the left, reading on the right, the way the built-in chart
        // fields lay their heading out. The label is the first thing to go when
        // the field is small: a quarter-screen field cannot carry a label, a
        // reading and a picture without all three being useless.
        var headingFont = fontFitting(dc, height * 34 / 100);
        var headingHeight = dc.getFontHeight(headingFont);
        var showLabel = (height >= 60) && (width >= 100);

        if (showLabel) {
            dc.setColor(foreground, Graphics.COLOR_TRANSPARENT);
            dc.drawText(2, 0, Graphics.FONT_XTINY, _label, Graphics.TEXT_JUSTIFY_LEFT);
        }

        var depth = _model.depth;
        var text = _model.formatDepth(depth);
        if (depth != null) {
            text += " " + _model.unitLabel();
        }
        dc.setColor(DepthCore.depthColor(depth, _model.color_profile), Graphics.COLOR_TRANSPARENT);
        dc.drawText(showLabel ? width - 2 : width / 2, 0, headingFont, text,
            showLabel ? Graphics.TEXT_JUSTIFY_RIGHT : Graphics.TEXT_JUSTIFY_CENTER);

        if (_style == STYLE_GAUGE) {
            drawGauge(dc, width, headingHeight, height - 1, foreground);
        } else {
            drawChart(dc, width, headingHeight, height - 1, foreground);
        }
    }

    //! Which style to draw in.
    //!
    //! Read straight from the properties rather than through DepthModel, which
    //! is shared with three other apps: how this one field draws itself is no
    //! business of the depth model. The guard is the same one the barrel uses —
    //! Properties.getValue() throws on a key the app never declared.
    private function styleSetting() as Number {
        try {
            var value = Properties.getValue("fieldStyle");
            if (value instanceof Lang.Number) {
                return value;
            }
        } catch (e) {
        }
        return STYLE_CHART;
    }

    //! The largest text font whose line height fits in the given space.
    //!
    //! Text fonts rather than the numeric ones the widget uses: those hold
    //! digits only, so they cannot render "n/a" or the unit, and a data field
    //! is too small for the size they buy to be worth two draws.
    private function fontFitting(dc as Dc, available as Number) as Graphics.FontType {
        var fonts = [
            Graphics.FONT_LARGE,
            Graphics.FONT_MEDIUM,
            Graphics.FONT_SMALL,
            Graphics.FONT_TINY,
        ] as Array<Graphics.FontType>;

        for (var i = 0; i < fonts.size(); i += 1) {
            if (dc.getFontHeight(fonts[i]) <= available) {
                return fonts[i];
            }
        }
        return Graphics.FONT_XTINY;
    }

    //! The depth trace over time, as a line deepening downwards.
    private function drawChart(dc as Dc, width as Number, top as Number, bottom as Number,
                               foreground as Graphics.ColorType) as Void {
        var span = bottom - top;
        if (span < 8 || width < 8) {
            return; // Nothing legible fits.
        }

        var scale = chartScale();

        // The surface, which is the line every reading is measured from and the
        // only part of the chart that means something on its own.
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(0, top, width, top);

        // Time runs left to right with the newest sample at the right edge, and
        // the axis is fixed at history_samples wide however much history there
        // is — so a fresh field fills in from the right rather than stretching
        // ten seconds across two minutes of chart.
        dc.setPenWidth(2);
        var previousX = -1;
        var previousY = 0;

        for (var x = 0; x < width; x += 1) {
            var age = ((width - 1 - x) * history_samples) / width;
            if (age >= _filled) {
                continue;
            }

            var centimeters = _history[(_next - 1 - age + 2 * history_samples) % history_samples];
            if (centimeters == no_reading) {
                previousX = -1; // A gap in the trace, not a line across it.
                continue;
            }

            var y = top + (span * centimeters) / scale;
            if (y > bottom) {
                y = bottom;
            }

            dc.setColor(DepthCore.depthColor(centimeters / 100.0, _model.color_profile),
                Graphics.COLOR_TRANSPARENT);
            if (previousX < 0) {
                dc.drawPoint(x, y);
            } else {
                dc.drawLine(previousX, previousY, x, y);
            }
            previousX = x;
            previousY = y;
        }
        dc.setPenWidth(1);

        // The session maximum, which is what the eye is usually looking for and
        // may well be older than the trace. Orange, as on the widget's own
        // maximum, and drawn last so the trace cannot hide it.
        var maximum = _model.max_depth;
        if (maximum != null) {
            var y = top + (span * DepthCore.depthCentimeters(maximum)) / scale;
            if (y <= bottom) {
                dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(0, y, width, y);
            }
        }

        // What the bottom of the chart is worth, without which the trace has
        // shape but no size. Skipped when the chart is too short to spare the
        // line — the reading above is still there.
        if (span >= 40) {
            dc.setColor(foreground, Graphics.COLOR_TRANSPARENT);
            dc.drawText(1, bottom - dc.getFontHeight(Graphics.FONT_XTINY),
                Graphics.FONT_XTINY, _model.formatDepth(scale / 100.0) + " " + _model.unitLabel(),
                Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    //! Where the current depth sits in the colour range, as a zoned bar.
    //!
    //! The zones are the colour profile's own boundaries, so the bar and the
    //! reading above it always agree about what colour a depth is.
    private function drawGauge(dc as Dc, width as Number, top as Number, bottom as Number,
                               foreground as Graphics.ColorType) as Void {
        var span = bottom - top;
        if (span < 8 || width < 24) {
            return;
        }

        var bands = DepthCore.profileBands(_model.color_profile);

        // Full scale gives the red zone a width of its own — ending the bar at
        // the red boundary would leave the last zone infinitely thin, and a
        // gauge that pins the moment it turns red says nothing after that.
        var scale = bands[2] + (bands[2] - bands[1]);

        // A bar thick enough to read but not so thick it swallows a short
        // field, centred in what is left below the reading.
        var thickness = span * 40 / 100;
        if (thickness > 18) {
            thickness = 18;
        }
        if (thickness < 5) {
            thickness = 5;
        }
        var barTop = top + (span - thickness) / 2;
        var left = 2;
        var barWidth = width - 4;

        // The four zones, laid down left to right. Each is drawn from where the
        // last one ended, so rounding cannot leave a gap between them.
        var edges = [bands[0], bands[1], bands[2], scale] as Array<Float>;
        var colors = [
            Graphics.COLOR_BLUE,
            Graphics.COLOR_GREEN,
            Graphics.COLOR_YELLOW,
            Graphics.COLOR_RED,
        ] as Array<Graphics.ColorType>;

        var x = left;
        for (var i = 0; i < edges.size(); i += 1) {
            var end = left + ((barWidth * edges[i]) / scale).toNumber();
            if (i == edges.size() - 1) {
                end = left + barWidth; // The last zone owns the rounding.
            }
            if (end > x) {
                dc.setColor(colors[i], Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x, barTop, end - x, thickness);
            }
            x = end;
        }

        // The session maximum, as a tick standing on the bar.
        var maximum = _model.max_depth;
        if (maximum != null && maximum > 0.0) {
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            var maxX = markerX(maximum, scale, left, barWidth);
            dc.drawLine(maxX, barTop - 2, maxX, barTop + thickness + 2);
        }

        // The current reading, in the foreground colour so it stands out
        // against whichever zone it happens to be sitting on.
        var depth = _model.depth;
        if (depth != null) {
            dc.setColor(foreground, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(3);
            var depthX = markerX(depth, scale, left, barWidth);
            dc.drawLine(depthX, barTop - 3, depthX, barTop + thickness + 3);
        }
        dc.setPenWidth(1);
    }

    //! Where a depth falls along the gauge, clamped to the bar.
    private function markerX(meters as Float, scale as Float, left as Number,
                             barWidth as Number) as Number {
        var position = (barWidth * meters / scale).toNumber();
        if (position < 0) {
            position = 0;
        }
        if (position > barWidth) {
            position = barWidth;
        }
        return left + position;
    }

    //! What the bottom edge of the chart is worth, in centimeters.
    private function chartScale() as Number {
        var deepest = 0;

        // The maximum needs two samples to agree with each other before it
        // moves; the trace does not, so it can hold something deeper.
        var maximum = _model.max_depth;
        if (maximum != null) {
            deepest = DepthCore.depthCentimeters(maximum);
        }

        for (var i = 0; i < _filled; i += 1) {
            var centimeters = _history[i];
            if (centimeters > deepest) {
                deepest = centimeters;
            }
        }

        for (var i = 0; i < scale_steps.size(); i += 1) {
            if (deepest <= scale_steps[i]) {
                return scale_steps[i];
            }
        }
        return deepest;
    }
}
