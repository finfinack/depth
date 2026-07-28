import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import DepthCore;

//! A depth trace for the last couple of minutes, drawn by the field itself.
//!
//! The other two fields are SimpleDataFields: they hand a string to the system
//! and the system draws it. That is all a SimpleDataField can do, so a graph
//! has to be a full DataField, which gets an onUpdate(dc) and the whole area to
//! itself — and with it the job of drawing the label, picking a font that fits,
//! and honouring the day/night background the system chose.
//!
//! This one records nothing. The per-record depth series and the raw pressure
//! belong to the Depth field and the session maximum to the Max Depth field;
//! writing them here as well would duplicate the whole graph in Garmin Connect
//! for anyone running two of these at once. Pair it with the Depth field if the
//! activity should carry the data as well as show it.
class depth_graphView extends WatchUi.DataField {

    // Two minutes at the one sample per second compute() is called at: long
    // enough to hold several breath-hold dives, short enough that the trace is
    // still legible across a quarter-screen field.
    const history_samples = 120;

    // "No reading", which is not the same as 0 cm — that is the surface.
    const no_reading = -1;

    // Depths the graph snaps its bottom edge to, in centimeters. Fixed steps
    // rather than a continuous fit to the deepest sample, so the trace holds
    // still instead of creeping up the field every time the maximum gains a
    // centimeter.
    const scale_steps = [200, 500, 1000, 2000, 3000, 5000, 10000] as Array<Number>;

    private var _model as DepthModel;
    private var _label as String;

    // Depth history in centimeters, as a ring buffer. Centimeters in a Number
    // rather than metres in a Float: the resolution the FIT file already
    // records at, and the graph is drawn in whole pixels anyway.
    private var _history as Array<Number>;
    private var _next as Number = 0;
    private var _filled as Number = 0;

    function initialize() {
        DataField.initialize();

        _model = new DepthModel();
        _label = WatchUi.loadResource(Rez.Strings.FieldLabel) as String;

        _history = new [history_samples] as Array<Number>;
        for (var i = 0; i < history_samples; i += 1) {
            _history[i] = no_reading;
        }
    }

    //! Called by the app when the user changes a setting.
    function onSettingsChanged() as Void {
        _model.loadSettings();
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

        // The label is the first thing to go when the field is small. The trace
        // is the point of this field, and a quarter-screen field cannot carry
        // a label, a value and a graph without all three being useless.
        var labelHeight = 0;
        if (height >= 70) {
            labelHeight = dc.getFontHeight(Graphics.FONT_XTINY);
            dc.setColor(foreground, Graphics.COLOR_TRANSPARENT);
            dc.drawText(width / 2, 0, Graphics.FONT_XTINY, _label,
                Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Roughly the top third for the reading, the rest for the trace.
        var valueFont = fontFitting(dc, (height - labelHeight) * 40 / 100);
        var valueHeight = dc.getFontHeight(valueFont);

        var depth = _model.depth;
        var text = _model.formatDepth(depth);
        if (depth != null) {
            text += " " + _model.unitLabel();
        }
        dc.setColor(DepthCore.depthColor(depth, _model.color_profile), Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, labelHeight, valueFont, text, Graphics.TEXT_JUSTIFY_CENTER);

        drawGraph(dc, width, labelHeight + valueHeight, height - 1, foreground);
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

    //! The depth trace, as a column of water per pixel, deepening downwards.
    private function drawGraph(dc as Dc, width as Number, top as Number, bottom as Number,
                               foreground as Graphics.ColorType) as Void {
        var span = bottom - top;
        if (span < 8 || width < 8) {
            return; // Nothing legible fits.
        }

        var scale = graphScale();

        // Time runs left to right with the newest sample at the right edge, and
        // the axis is fixed at history_samples wide however much history there
        // is — so a fresh field fills in from the right rather than stretching
        // ten seconds across two minutes of graph.
        for (var x = 0; x < width; x += 1) {
            var age = ((width - 1 - x) * history_samples) / width;
            if (age >= _filled) {
                continue;
            }

            var centimeters = _history[(_next - 1 - age + 2 * history_samples) % history_samples];
            if (centimeters == no_reading) {
                continue;
            }

            var y = top + (span * centimeters) / scale;
            if (y > bottom) {
                y = bottom;
            }

            dc.setColor(DepthCore.depthColor(centimeters / 100.0, _model.color_profile),
                Graphics.COLOR_TRANSPARENT);
            dc.drawLine(x, top, x, y);
        }

        // The session maximum, which is what the eye is usually looking for and
        // may well be older than the trace. Orange, as on the widget's own
        // maximum, and drawn last so the trace cannot hide it.
        var maximum = _model.max_depth;
        if (maximum != null) {
            var y = top + (span * DepthCore.depthCentimeters(maximum)) / scale;
            if (y <= bottom) {
                dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(1);
                dc.drawLine(0, y, width, y);
            }
        }

        // What the bottom of the graph is worth, without which the trace has
        // shape but no size. Skipped when the graph is too short to spare the
        // line — the reading above is still there.
        if (span >= 40) {
            dc.setColor(foreground, Graphics.COLOR_TRANSPARENT);
            dc.drawText(1, bottom - dc.getFontHeight(Graphics.FONT_XTINY),
                Graphics.FONT_XTINY, _model.formatDepth(scale / 100.0) + " " + _model.unitLabel(),
                Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    //! What the bottom edge of the graph is worth, in centimeters.
    private function graphScale() as Number {
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
