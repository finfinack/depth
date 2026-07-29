import Toybox.Activity;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import DepthCore;

//! Depth as a chart of the last couple of minutes, laid out like the watch's
//! own barometer field: a solid body of water hanging from the surface line,
//! deepening downwards, with the reading above it.
//!
//! The Depth and Max Depth fields are SimpleDataFields: they hand a string to
//! the system and the system draws it. That is all a SimpleDataField can do, so
//! anything with a shape has to be a full DataField, which gets an onUpdate(dc)
//! and the whole area to itself — and with it the job of drawing the label,
//! picking a font that fits, honouring the day/night background the system
//! chose, and staying inside the lens of a round screen. The last of those is
//! DepthFieldLayout's, in the barrel, because Depth Gauge has the same problem.
//!
//! This one records nothing. The per-record depth series and the raw pressure
//! belong to the Depth field and the session maximum to the Max Depth field;
//! writing them here as well would duplicate the whole graph in Garmin Connect
//! for anyone running two of these at once. Pair it with the Depth field if the
//! activity should carry the data as well as show it.
class depth_chartView extends WatchUi.DataField {

    // Two minutes at the one sample per second compute() is called at: long
    // enough to hold several breath-hold dives, short enough that the trace is
    // still legible across a quarter-screen field.
    const history_samples = 120;

    // "No reading", which is not the same as 0 cm — that is the surface.
    const no_reading = -1;

    // The shallowest the chart will ever scale to, in centimeters. The bottom
    // edge is the session maximum, and a maximum of two centimeters would
    // otherwise stretch the sensor's own noise across the whole field. Half a
    // metre is already inside the band the model treats as "at the surface".
    const min_scale = 50;

    private var _model as DepthModel;
    private var _layout as DepthFieldLayout;
    private var _label as String;
    private var _maxLabel as String;

    // Depth history in centimeters, as a ring buffer. Centimeters in a Number
    // rather than metres in a Float: the resolution the FIT file already
    // records at, and the chart is drawn in whole pixels anyway.
    private var _history as Array<Number>;
    private var _next as Number = 0;
    private var _filled as Number = 0;

    function initialize() {
        DataField.initialize();

        _model = new DepthModel(DepthCore.REZERO_HANDLE);
        _layout = new DepthFieldLayout();
        _label = WatchUi.loadResource(Rez.Strings.FieldLabel) as String;
        _maxLabel = WatchUi.loadResource(Rez.Strings.LabelMax) as String;

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
        // getObscurityFlags() is only valid from here, so the layout is
        // measured here too. It recomputes only when the field has actually
        // moved or been resized, which in practice is once.
        _layout.update(dc, getObscurityFlags());

        // The system picks the background: white in day mode, black at night,
        // and a field that ignores it is unreadable in one of the two.
        var background = getBackgroundColor();
        var foreground = (background == Graphics.COLOR_WHITE)
            ? Graphics.COLOR_BLACK
            : Graphics.COLOR_WHITE;

        dc.setColor(background, background);
        dc.clear();

        drawChart(dc, drawHeading(dc, foreground), foreground);
    }

    //! The field's label and the current reading, on one row above the chart,
    //! the way the built-in chart fields head themselves. Returns the first row
    //! below it, which is where the chart starts.
    //!
    //! The label is the first thing to go when the field is small: a
    //! quarter-screen field cannot carry a label, a reading and a picture
    //! without all three being useless, and the system has already shown the
    //! user the field's name on the screen they picked it from. Whether it fits
    //! is measured rather than guessed at, so a long translation drops the
    //! label instead of colliding with the reading.
    private function drawHeading(dc as Dc, foreground as Graphics.ColorType) as Number {
        var top = _layout.top();
        var bottom = _layout.bottom();

        var depth = _model.depth;
        var limited = _model.saturated;
        var text = _model.formatBounded(depth, limited);
        if (depth != null) {
            text += " " + _model.unitLabel();
        }
        text += _model.staleMark(depth);

        var font = _layout.fontFitting(dc, text, _layout.right(top, bottom) - _layout.left(top, bottom),
            (bottom - top) * 34 / 100);
        var lineHeight = dc.getFontHeight(font);
        var headingBottom = top + lineHeight;

        var x0 = _layout.left(top, headingBottom);
        var x1 = _layout.right(top, headingBottom);

        var labelWidth = dc.getTextWidthInPixels(_label, Graphics.FONT_XTINY);
        var textWidth = dc.getTextWidthInPixels(text, font);
        var showLabel = (bottom - top) >= 60 && (labelWidth + textWidth + 6) <= (x1 - x0);

        if (showLabel) {
            dc.setColor(foreground, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x0, top, Graphics.FONT_XTINY, _label, Graphics.TEXT_JUSTIFY_LEFT);
        }

        dc.setColor(DepthCore.readingColor(depth, _model.color_profile, limited),
            Graphics.COLOR_TRANSPARENT);
        dc.drawText(showLabel ? x1 : (x0 + x1) / 2, top, font, text,
            showLabel ? Graphics.TEXT_JUSTIFY_RIGHT : Graphics.TEXT_JUSTIFY_CENTER);

        return headingBottom;
    }

    //! The depth trace over time, drawn as the water above the diver.
    //!
    //! The barometer field fills the area between its axis and its trace, and
    //! the same fill means something here: depth is measured down from the
    //! surface, so the block between the surface line and the trace *is* the
    //! reading, and the chart reads as a body of water rather than a line.
    //!
    //! It is banded by the colour profile as it deepens, so the fill carries
    //! the same blue/green/yellow/red the reading above it does — and the bands
    //! are horizontal, at fixed depths, so they can be read as a scale.
    private function drawChart(dc as Dc, top as Number, foreground as Graphics.ColorType) as Void {
        var bottom = _layout.bottom();
        var width = _layout.width();

        // bottom() is one past the last row, so the deepest the trace can be
        // drawn on is the row before it — and that row, not bottom, is what a
        // full-scale reading has to land on.
        var lastRow = bottom - 1;
        var span = lastRow - top;
        if (span < 8 || width < 8) {
            return; // Nothing legible fits.
        }

        var scale = chartScale();

        // The surface, which is the line every reading is measured from and the
        // only part of the chart that means something on its own.
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(_layout.rowLeft(top), top, _layout.rowRight(top), top);

        // The rows the colour changes at, worked out once rather than per
        // column. A band deeper than the chart goes lands past lastRow and the
        // clamping below drops it.
        var bands = DepthCore.profileBands(_model.color_profile);
        var bandRows = [
            rowFor(bands[0], top, span, scale),
            rowFor(bands[1], top, span, scale),
            rowFor(bands[2], top, span, scale),
        ] as Array<Number>;
        var bandColors = [
            Graphics.COLOR_BLUE,
            Graphics.COLOR_GREEN,
            Graphics.COLOR_YELLOW,
            Graphics.COLOR_RED,
        ] as Array<Graphics.ColorType>;

        // Time runs left to right with the newest sample at the right edge, and
        // the axis is fixed at history_samples wide however much history there
        // is — so a fresh field fills in from the right rather than stretching
        // ten seconds across two minutes of chart.
        //
        // The axis spans the field rather than a rectangle inside the lens, and
        // each column is clipped to where it enters and leaves the lens: on a
        // round screen the water then takes the shape of the lens, which is
        // both what there is room for and what the watch's own charts look
        // like. Squaring it off inside would throw away most of a corner field.
        for (var x = 0; x < width; x += 1) {
            var age = ((width - 1 - x) * history_samples) / width;
            if (age >= _filled) {
                continue;
            }

            var centimeters = _history[(_next - 1 - age + 2 * history_samples) % history_samples];
            if (centimeters == no_reading) {
                continue; // A gap in the water, not a column drawn through it.
            }

            var surface = _layout.columnTop(x);
            if (surface < top + 1) {
                surface = top + 1;
            }
            var y = top + (span * centimeters) / scale;
            if (y > lastRow) {
                y = lastRow;
            }
            var floor = _layout.columnBottom(x);
            if (floor > y) {
                floor = y;
            }
            if (floor < surface) {
                continue; // This column is off the lens entirely.
            }

            fillColumn(dc, x, surface, floor, bandRows, bandColors);

            // A crisp edge where the water stops, so the trace still reads as a
            // line over time rather than only as a change of colour.
            if (y == floor) {
                dc.setColor(foreground, Graphics.COLOR_TRANSPARENT);
                dc.drawPoint(x, y);
            }
        }

        drawMaximum(dc, top, span, scale, lastRow);
    }

    //! One column of water, banded by the colour profile on the way down.
    private function fillColumn(dc as Dc, x as Number, from as Number, to as Number,
                                bandRows as Array<Number>,
                                bandColors as Array<Graphics.ColorType>) as Void {
        var start = from;
        for (var i = 0; i < bandColors.size(); i += 1) {
            // The last band owns everything below the deepest boundary.
            var end = (i < bandRows.size()) ? bandRows[i] : to + 1;
            if (end > to + 1) {
                end = to + 1;
            }
            if (end > start) {
                dc.setColor(bandColors[i], Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x, start, 1, end - start);
                start = end;
            }
            if (start > to) {
                return;
            }
        }
    }

    //! The session maximum, which is the bottom of the chart.
    //!
    //! The chart scales to it rather than to fixed steps, so the deepest the
    //! diver has been is the floor of the picture and there is only one
    //! reference on the chart to read — an orange line along the bottom with
    //! its depth on it. A line floating in the middle of a chart reads as a
    //! threshold or an average just as readily as a maximum, which is what the
    //! fixed steps used to leave behind.
    //!
    //! It is drawn at the maximum's own row rather than always at lastRow,
    //! because min_scale can put the floor deeper than anything reached — in
    //! which case the line is where the maximum really is, and still labelled.
    private function drawMaximum(dc as Dc, top as Number, span as Number,
                                 scale as Number, lastRow as Number) as Void {
        var maximum = _model.max_depth;
        if (maximum == null) {
            return;
        }

        var y = rowFor(maximum, top, span, scale);
        if (y > lastRow) {
            y = lastRow;
        }

        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(_layout.rowLeft(y), y, _layout.rowRight(y), y);

        // Its depth, on the row above the line, where the water has not reached
        // unless the diver is at the maximum right now.
        if (span < 40) {
            return;
        }
        var lineHeight = dc.getFontHeight(Graphics.FONT_XTINY);
        var textTop = y - lineHeight;
        if (textTop < top) {
            return;
        }

        var text = _maxLabel + " " + _model.formatBounded(maximum, _model.saturation_seen)
            + " " + _model.unitLabel() + _model.staleMark(maximum);
        var textLeft = _layout.left(textTop, y);
        if (dc.getTextWidthInPixels(text, Graphics.FONT_XTINY) > _layout.right(textTop, y) - textLeft) {
            return;
        }
        dc.drawText(textLeft, textTop, Graphics.FONT_XTINY, text, Graphics.TEXT_JUSTIFY_LEFT);
    }

    //! Which row a depth in metres falls on.
    private function rowFor(meters as Float, top as Number, span as Number,
                            scale as Number) as Number {
        return top + (span * DepthCore.depthCentimeters(meters)) / scale;
    }

    //! What the bottom edge of the chart is worth, in centimeters: the deepest
    //! the session has been, so the maximum sits on the floor of the picture.
    //!
    //! The session maximum and nothing else. This used to take the deepest
    //! sample in the history buffer as well, because the maximum was confirmed
    //! by agreement between consecutive samples and so lagged the trace by a
    //! sample of descent rate. It no longer does — the model accepts a peak on
    //! the sample it happens, given a descent leading into it — so the only
    //! readings the buffer can now hold that the maximum will not are ones the
    //! model has *rejected* as glitches.
    //!
    //! Scaling to those was worse than clipping them. It let one bad sample
    //! squash the whole trace, and it pushed the orange maximum line up off the
    //! floor — which is the exact failure scaling to the maximum was meant to
    //! fix, since a line floating mid-chart reads as a threshold rather than as
    //! a maximum. A rejected sample now clamps to the bottom row instead, in
    //! drawChart(), which is the honest rendering of a reading nothing else
    //! believes.
    private function chartScale() as Number {
        var deepest = min_scale;

        var maximum = _model.max_depth;
        if (maximum != null) {
            var centimeters = DepthCore.depthCentimeters(maximum);
            if (centimeters > deepest) {
                deepest = centimeters;
            }
        }
        return deepest;
    }
}
