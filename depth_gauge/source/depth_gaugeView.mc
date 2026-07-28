import Toybox.Activity;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;
import DepthCore;

//! Depth as a zoned gauge: where the current reading sits in the colour range,
//! the way the watch's own heart rate gauge shows a zone.
//!
//! It is drawn two ways, because a data field can be handed anything from the
//! whole screen to a band a few rows tall, and one shape cannot serve both:
//!
//! - As an **arc**, the upper half of a zone gauge, when the field is tall
//!   enough to carry a semicircle that actually uses its width. On a full-screen
//!   or top-half field the arc is concentric with the display, so it runs along
//!   the bezel exactly like the built-in gauges.
//! - As a **bar** otherwise, which is every three- and four-field layout. A
//!   semicircle is limited by the field's height, so in a band 65 rows tall it
//!   would span a third of the width and squeeze the reading into what was left
//!   — backwards, because the reading is the point and the gauge is context.
//!
//! The Depth and Max Depth fields are SimpleDataFields: they hand a string to
//! the system and the system draws it. That is all a SimpleDataField can do, so
//! anything with a shape has to be a full DataField, which gets an onUpdate(dc)
//! and the whole area to itself — and with it the job of drawing the label,
//! picking a font that fits, honouring the day/night background the system
//! chose, and staying inside the lens of a round screen. The last of those is
//! DepthFieldLayout's, in the barrel, because Depth Chart has the same problem.
//!
//! This one records nothing. The per-record depth series and the raw pressure
//! belong to the Depth field and the session maximum to the Max Depth field;
//! writing them here as well would duplicate the whole graph in Garmin Connect
//! for anyone running two of these at once. Pair it with the Depth field if the
//! activity should carry the data as well as show it.
class depth_gaugeView extends WatchUi.DataField {

    // The arc runs across the top of the field, left to right: 180 degrees is
    // due west and 0 due east in the Dc's own convention, and clockwise between
    // them goes over the top.
    const arc_start_degrees = 180;
    const arc_end_degrees = 0;

    // Thickness of the band as a percentage of the arc's radius or of the
    // field's height, and the bounds that keep it readable on a big field and
    // drawable on a small one.
    const band_thickness_percent = 22;
    const band_min_thickness = 4;
    const band_max_thickness = 14;

    // What an arc has to manage to be worth drawing instead of a bar: a radius
    // whose inside can hold a legible reading, and a span that is most of the
    // field's width rather than a token curve in the middle of it.
    const arc_min_radius = 40;
    const arc_min_width_percent = 75;

    // The marker that rides the gauge at the current depth.
    const marker_height = 7;
    const marker_half_width = 5;

    // Shallow to deep. The boundaries between them are the colour profile's
    // own, so the gauge and the reading cannot disagree about a depth.
    const zone_colors = [
        Graphics.COLOR_BLUE,
        Graphics.COLOR_GREEN,
        Graphics.COLOR_YELLOW,
        Graphics.COLOR_RED,
    ] as Array<Graphics.ColorType>;

    private var _model as DepthModel;
    private var _layout as DepthFieldLayout;
    private var _label as String;
    private var _maxLabel as String;

    function initialize() {
        DataField.initialize();

        _model = new DepthModel();
        _layout = new DepthFieldLayout();
        _label = WatchUi.loadResource(Rez.Strings.FieldLabel) as String;
        _maxLabel = WatchUi.loadResource(Rez.Strings.LabelMax) as String;
    }

    //! Called by the app when the user changes a setting.
    function onSettingsChanged() as Void {
        _model.loadSettings();
    }

    //! Read the sensor. Called about once a second.
    //!
    //! Nothing is kept between calls: the gauge shows where the reading is now,
    //! and the model already holds the maximum.
    function compute(info as Activity.Info) as Void {
        _model.update(info);
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

        if (!drawArcGauge(dc, foreground)) {
            drawBarGauge(dc, foreground);
        }
    }

    //! The gauge as an arc, with the reading inside it. Returns false without
    //! drawing anything when the field is the wrong shape for one.
    private function drawArcGauge(dc as Dc, foreground as Graphics.ColorType) as Boolean {
        var top = _layout.top();
        var bottom = _layout.bottom();
        var left = _layout.left(top, bottom);
        var right = _layout.right(top, bottom);

        // Concentric with the lens whenever the field can hold the whole upper
        // half of it. An arc concentric with the lens is on the lens at every
        // point, so it needs no room inside a rectangle — which is why it asks
        // the layout for the circle rather than for left()/right(). Fitting it
        // into a box instead shrinks it to about half the screen it could use.
        var centerX = _layout.lensCenterX();
        var centerY = _layout.lensCenterY();
        var radius = _layout.lensRadius();
        var concentric = (radius > 0)
            && (centerX - radius >= 0) && (centerX + radius <= _layout.width())
            && (centerY - radius >= 0) && (centerY <= _layout.height());

        if (!concentric) {
            // A semicircle fitted into the field instead: twice as wide as it
            // is tall, so its radius is whichever the field runs out of first.
            radius = (right - left) / 2;
            if (radius > bottom - top - 1) {
                radius = bottom - top - 1;
            }
            centerX = (left + right) / 2;
            centerY = top + radius;

            // Being height-limited is what makes it the wrong shape for a wide,
            // short field: the curve would take a third of the width and leave
            // the reading the scraps. Hand those fields to the bar.
            if (radius < arc_min_radius
                || 2 * radius < (right - left) * arc_min_width_percent / 100) {
                return false;
            }
        }

        var thickness = bandThickness(radius);

        // drawArc strokes on both sides of the radius it is given, so the band
        // is pulled in by half its thickness to keep its outer edge on the arc.
        var bandRadius = radius - thickness / 2;

        var edges = zoneEdges();
        var scale = edges[edges.size() - 1];

        dc.setPenWidth(thickness);
        for (var i = 0; i < zone_colors.size(); i += 1) {
            var from = degreesFor(edges[i], scale);
            var to = degreesFor(edges[i + 1], scale);
            if (from <= to) {
                continue; // A zone with no width, on a profile that has one.
            }
            dc.setColor(zone_colors[i], Graphics.COLOR_TRANSPARENT);
            dc.drawArc(centerX, centerY, bandRadius, Graphics.ARC_CLOCKWISE, from, to);
        }
        dc.setPenWidth(1);

        // The session maximum, straight across the band rather than along it: a
        // short arc in another colour would just read as one more zone.
        var maximum = _model.max_depth;
        if (maximum != null && maximum > 0.0) {
            var angle = Math.toRadians(degreesFor(maximum, scale));
            var out_x = Math.cos(angle);
            var out_y = -Math.sin(angle);
            var inner = bandRadius - thickness / 2.0;
            var outer = bandRadius + thickness / 2.0;

            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(3);
            dc.drawLine((centerX + inner * out_x).toNumber(), (centerY + inner * out_y).toNumber(),
                (centerX + outer * out_x).toNumber(), (centerY + outer * out_y).toNumber());
            dc.setPenWidth(1);
        }

        // The current depth, as an arrowhead riding just inside the band.
        var depth = _model.depth;
        if (depth != null) {
            dc.setColor(foreground, Graphics.COLOR_TRANSPARENT);
            drawArrowhead(dc, centerX, centerY, bandRadius - thickness / 2 - 1,
                degreesFor(depth, scale));
        }

        // The reading goes inside the arc, as it does on the heart rate gauge:
        // the number is what is being read and the arc is context around it.
        var room = bandRadius - thickness / 2;
        drawReading(dc, centerX, centerY - room * 2 / 5, room * 8 / 5, room * 4 / 5, foreground);
        return true;
    }

    //! The gauge as a bar along the bottom of the field with the reading above
    //! it, which is what every short, wide field gets.
    private function drawBarGauge(dc as Dc, foreground as Graphics.ColorType) as Void {
        var top = _layout.top();
        var bottom = _layout.bottom();

        var thickness = bandThickness(bottom - top);
        var barTop = bottom - thickness - 1;

        // The span is asked for over the rows the marker reaches, not just the
        // rows of the bar, so nothing standing above it lands in the bezel.
        var bandTop = barTop - marker_height;
        if (bandTop < top) {
            bandTop = top;
        }
        var left = _layout.left(bandTop, bottom);
        var right = _layout.right(bandTop, bottom);
        var barWidth = right - left;

        if (barWidth < 24 || bandTop <= top) {
            // No room for a gauge at all. The reading is the point, so it gets
            // the whole field rather than sharing it with an illegible bar.
            drawReading(dc, (_layout.left(top, bottom) + _layout.right(top, bottom)) / 2,
                (top + bottom) / 2,
                _layout.right(top, bottom) - _layout.left(top, bottom), bottom - top, foreground);
            return;
        }

        var edges = zoneEdges();
        var scale = edges[edges.size() - 1];

        // Each zone starts where the last one ended, so rounding cannot leave a
        // gap between them.
        var x = left;
        for (var i = 0; i < zone_colors.size(); i += 1) {
            var end = (i == zone_colors.size() - 1)
                ? left + barWidth // The last zone owns the rounding.
                : left + ((barWidth * edges[i + 1]) / scale).toNumber();
            if (end > x) {
                dc.setColor(zone_colors[i], Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x, barTop, end - x, thickness);
            }
            x = end;
        }

        // The session maximum, straight across the bar, for the same reason the
        // arc draws it across the band.
        var maximum = _model.max_depth;
        if (maximum != null && maximum > 0.0) {
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(3);
            var maxX = markerX(maximum, scale, left, barWidth);
            dc.drawLine(maxX, barTop, maxX, barTop + thickness);
            dc.setPenWidth(1);
        }

        // The current depth, as the same arrowhead, pointing down onto the bar.
        var depth = _model.depth;
        if (depth != null) {
            var depthX = markerX(depth, scale, left, barWidth);
            dc.setColor(foreground, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([
                [depthX, barTop - 1],
                [depthX - marker_half_width, barTop - 1 - marker_height],
                [depthX + marker_half_width, barTop - 1 - marker_height],
            ] as Array<[Numeric, Numeric]>);
        }

        drawReading(dc, (left + right) / 2, (top + bandTop) / 2, barWidth, bandTop - top,
            foreground);
    }

    //! The four zone boundaries in metres, shallow to deep, the last of which is
    //! what the deep end of the gauge is worth.
    //!
    //! Full scale gives the red zone a width of its own — ending the gauge at
    //! the red boundary would leave the last zone infinitely thin, and a gauge
    //! that pins the moment it turns red says nothing after that.
    private function zoneEdges() as Array<Float> {
        var bands = DepthCore.profileBands(_model.color_profile);
        return [0.0, bands[0], bands[1], bands[2], bands[2] + (bands[2] - bands[1])]
            as Array<Float>;
    }

    //! How thick the coloured band is, given the size it has to sit in.
    private function bandThickness(available as Number) as Number {
        var thickness = available * band_thickness_percent / 100;
        if (thickness > band_max_thickness) {
            return band_max_thickness;
        }
        return (thickness < band_min_thickness) ? band_min_thickness : thickness;
    }

    //! An arrowhead pointing outwards along the arc's radius, its tip at
    //! `radius` and its base `marker_height` further in.
    private function drawArrowhead(dc as Dc, centerX as Number, centerY as Number,
                                   radius as Number, degrees as Float) as Void {
        var angle = Math.toRadians(degrees);
        // The Dc measures angles anticlockwise from due east, but y grows
        // downwards, so the outward unit vector is (cos, -sin) on screen and
        // the one across it is (sin, cos).
        var out_x = Math.cos(angle);
        var out_y = -Math.sin(angle);
        var across_x = -out_y;
        var across_y = out_x;

        var baseRadius = radius - marker_height;
        var baseX = centerX + baseRadius * out_x;
        var baseY = centerY + baseRadius * out_y;

        dc.fillPolygon([
            [(centerX + radius * out_x).toNumber(), (centerY + radius * out_y).toNumber()],
            [(baseX + marker_half_width * across_x).toNumber(),
                (baseY + marker_half_width * across_y).toNumber()],
            [(baseX - marker_half_width * across_x).toNumber(),
                (baseY - marker_half_width * across_y).toNumber()],
        ] as Array<[Numeric, Numeric]>);
    }

    //! The label, the reading and the session maximum, stacked and centred in
    //! the given box.
    //!
    //! The reading has first call on the space and the other two are dropped
    //! when what is left cannot hold them — a quarter-screen field cannot carry
    //! all three without all three being useless, and the system has already
    //! shown the user the field's name on the screen they picked it from.
    //! Whether they fit is measured rather than guessed at, so a long
    //! translation drops its line instead of running off the side.
    private function drawReading(dc as Dc, centerX as Number, centerY as Number,
                                 boxWidth as Number, boxHeight as Number,
                                 foreground as Graphics.ColorType) as Void {
        var depth = _model.depth;
        var text = _model.formatDepth(depth);
        if (depth != null) {
            text += " " + _model.unitLabel();
        }

        var smallHeight = dc.getFontHeight(Graphics.FONT_XTINY);

        // Leave room for both extra lines if anything at all fits that way,
        // and give the reading the whole box when nothing does.
        var font = _layout.fontFitting(dc, text, boxWidth, boxHeight - 2 * smallHeight);
        if (font == Graphics.FONT_XTINY) {
            font = _layout.fontFitting(dc, text, boxWidth, boxHeight);
        }
        var lineHeight = dc.getFontHeight(font);
        var spare = boxHeight - lineHeight;

        var maximum = _model.max_depth;
        var maxText = (maximum == null)
            ? ""
            : _maxLabel + " " + _model.formatDepth(maximum) + " " + _model.unitLabel();
        var showMax = (maxText.length() > 0) && (spare >= smallHeight)
            && (dc.getTextWidthInPixels(maxText, Graphics.FONT_XTINY) <= boxWidth);
        if (showMax) {
            spare -= smallHeight;
        }

        var showLabel = (spare >= smallHeight)
            && (dc.getTextWidthInPixels(_label, Graphics.FONT_XTINY) <= boxWidth);

        var used = lineHeight + (showLabel ? smallHeight : 0) + (showMax ? smallHeight : 0);
        var y = centerY - used / 2;

        if (showLabel) {
            dc.setColor(foreground, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, y, Graphics.FONT_XTINY, _label, Graphics.TEXT_JUSTIFY_CENTER);
            y += smallHeight;
        }

        dc.setColor(DepthCore.depthColor(depth, _model.color_profile), Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        y += lineHeight;

        if (showMax) {
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, y, Graphics.FONT_XTINY, maxText, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    //! Where a depth falls along the bar, clamped to it.
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

    //! Where a depth sits on the arc, in the Dc's degrees. Clamped to the ends:
    //! past full scale the marker pins at the deep end rather than wrapping
    //! round into the shallow one.
    private function degreesFor(meters as Float, scale as Float) as Float {
        var fraction = meters / scale;
        if (fraction < 0.0) {
            fraction = 0.0;
        }
        if (fraction > 1.0) {
            fraction = 1.0;
        }
        return arc_start_degrees - (arc_start_degrees - arc_end_degrees) * fraction;
    }
}
