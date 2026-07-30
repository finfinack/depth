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
//! - As an **arc** concentric with the display, sweeping over or under the lens
//!   centre, whenever the field spans the lens and holds one half of it. Only
//!   ever concentric: that is what puts it on the bezel, since an arc on the
//!   lens's own centre is on the lens at every point however large. Where the
//!   field stops short of the lens's diameter — a two-field top half is 129
//!   rows tall on a 260 row screen — the *sweep* is trimmed by a degree or two
//!   rather than the radius, which is worth about 100px of arc.
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

    // Thickness of the coloured band. The arc scales with its radius and the
    // bar with the field's height, so both are clamped: without a ceiling a
    // full-screen arc turns into a doughnut, and without a floor a four-field
    // band gets a line nobody can read a colour off.
    const band_min_thickness = 5;
    const arc_thickness_percent = 16;
    const arc_max_thickness = 34;
    const bar_thickness_percent = 26;
    const bar_max_thickness = 22;

    // The marker that rides the gauge at the current depth, as a percentage of
    // the band's thickness rather than a fixed size: an arrowhead that does not
    // grow with the band it points at looks like a speck on a full-screen gauge
    // and swamps the band on a four-field one.
    const marker_height_percent = 90;
    const marker_width_percent = 65;
    const marker_min_height = 6;
    const marker_min_half_width = 5;

    // What an arc has to manage to be worth drawing instead of a bar: an inside
    // big enough to hold a legible reading, and a sweep still long enough to
    // read as a scale rather than as a shallow smile across the top.
    const arc_min_radius = 40;
    const arc_max_trim_degrees = 15.0;

    // How far above and below the lens centre the reading's box reaches on a
    // full-screen gauge, as a percentage of the inside radius.
    //
    // It is a trade between the two dimensions: a taller box is a narrower one,
    // because both ends are bounded by the same circle. Half the radius, which
    // this used to be, leaves the box 1.73 times the radius across and the disc
    // three quarters empty — the reading was capped at the largest *text* font
    // with rows to spare. Three quarters buys about half again as many rows,
    // enough for a numeric font and the session totals under it, and still
    // leaves it 1.32 times the radius across, which is wider than the widest
    // line ever drawn into it.
    const arc_box_offset_percent = 75;

    // How tall the box has to be before the session totals are offered at all,
    // in rows of the small font: the label, a reading worth two of them, the
    // trend, the maximum, and the two totals themselves. Below that they would
    // reserve rows they go on to drop and shrink the reading to pay for it.
    const stats_min_lines = 7;

    // Numeric fonts, largest first. They hold digits, "." and ":" and nothing
    // else, which is why the unit, any ">=" and the stale mark are drawn beside
    // them rather than in them.
    const number_fonts = [
        Graphics.FONT_NUMBER_HOT,
        Graphics.FONT_NUMBER_MEDIUM,
        Graphics.FONT_NUMBER_MILD,
    ] as Array<Graphics.FontType>;

    // The sweep a field that holds the whole lens gets: 270 degrees with the
    // gap at the bottom, the way a speedometer runs and the way the watch's own
    // zone gauges do. 225 degrees is lower-left and -45 lower-right, and
    // clockwise between them passes over the top — so shallow stays on the left
    // exactly as it is on the half sweep, and the extra 90 degrees buys the
    // same four zones half again as much angular resolution.
    //
    // The end runs past zero into negative degrees on purpose: degreesFor() and
    // the marker trigonometry both need the sweep monotonic, and drawArc() gets
    // its own wrapped copy from arcDegrees().
    const full_sweep_start = 225.0;
    const full_sweep_end = -45.0;

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
    private var _divesLabel as String;
    private var _bottomLabel as String;

    function initialize() {
        DataField.initialize();

        _model = new DepthModel(DepthCore.REZERO_HANDLE);
        _layout = new DepthFieldLayout();
        _label = WatchUi.loadResource(Rez.Strings.FieldLabel) as String;
        _maxLabel = WatchUi.loadResource(Rez.Strings.LabelMax) as String;
        _divesLabel = WatchUi.loadResource(Rez.Strings.LabelDives) as String;
        _bottomLabel = WatchUi.loadResource(Rez.Strings.LabelBottomTime) as String;
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

    //! The gauge as an arc concentric with the display, sweeping over whichever
    //! half of the lens the field holds. Returns false without drawing anything
    //! when the field is the wrong shape for one.
    //!
    //! Concentric is the whole point: an arc on the lens's own centre is on the
    //! lens at every point, however large, so it can run right along the bezel
    //! like the built-in gauges. It asks the layout for the circle rather than
    //! for left()/right() for exactly that reason — a semicircle fitted inside
    //! a rectangle inside the lens comes out at about half the radius.
    private function drawArcGauge(dc as Dc, foreground as Graphics.ColorType) as Boolean {
        var width = _layout.width();
        var height = _layout.height();
        var centerX = _layout.lensCenterX();
        var centerY = _layout.lensCenterY();
        var lensRadius = _layout.lensRadius();

        // The field has to span the lens horizontally, which every full-width
        // field does and no half-width one can.
        if (lensRadius <= 0 || centerX - lensRadius < 0 || centerX + lensRadius > width) {
            return false;
        }

        var thickness = bandThickness(lensRadius, arc_thickness_percent, arc_max_thickness);

        // drawArc strokes on both sides of the radius it is given, so the band
        // is pulled in by half its thickness to keep its outer edge on the arc.
        var bandRadius = lensRadius - thickness / 2;
        var inside = bandRadius - thickness / 2;
        if (inside < arc_min_radius) {
            return false;
        }

        var startDegrees = 0.0;
        var endDegrees = 0.0;
        var boxTop = 0;
        var boxBottom = 0;
        var offset = 0;

        // A field holding the whole lens is a field the user gave the whole
        // screen to, so it gets the whole circle rather than half of one.
        var fullLens = (centerY - lensRadius >= 0) && (centerY + lensRadius <= height);

        if (fullLens) {
            startDegrees = full_sweep_start;
            endDegrees = full_sweep_end;

            // The reading sits at the centre of the lens, in a box reaching
            // arc_box_offset_percent of the inner radius above and below the
            // middle — see there for why that fraction and not another. Room
            // enough for the reading in a numeric font, the maximum, the label,
            // the trend and the session totals without any of them crowding.
            offset = inside * arc_box_offset_percent / 100;
            boxTop = centerY - offset;
            boxBottom = centerY + offset;
        } else {
            // Which half of the lens this field holds — the top or the bottom.
            var downwards = (centerY * 2 < height);
            var trim;
            if (downwards) {
                if (centerY + lensRadius > height) {
                    return false; // The bottom of the lens is outside the field.
                }
                trim = sweepTrim(-centerY, inside);
            } else {
                if (centerY - lensRadius < 0) {
                    return false; // The top of the lens is outside the field.
                }
                trim = sweepTrim(centerY - (height - 1), inside);
            }
            if (trim > arc_max_trim_degrees) {
                return false; // What is left of the sweep is a smile, not a scale.
            }

            // 180 degrees is due west and 0 due east, so the shallow end of the
            // scale is on the left either way and the sweep runs over the top or
            // under the bottom.
            startDegrees = downwards ? 180.0 + trim : 180.0 - trim;
            endDegrees = downwards ? 360.0 - trim : trim;

            // The reading goes inside the arc, as it does on the heart rate
            // gauge: the number is what is being read and the arc is context
            // around it. It takes the wide part of the inside, away from the
            // pinched apex, and is bounded by the chord at its own far edge so
            // it cannot overrun the band.
            if (downwards) {
                boxTop = (centerY > 0) ? centerY : 0;
                boxBottom = boxTop + ((centerY + inside) - boxTop) * 7 / 10;
                offset = boxBottom - centerY;
            } else {
                boxBottom = (centerY < height) ? centerY : height;
                boxTop = boxBottom - (boxBottom - (centerY - inside)) * 7 / 10;
                offset = centerY - boxTop;
            }
            if (offset < 0) {
                offset = 0;
            }
        }

        drawArcBand(dc, centerX, centerY, bandRadius, thickness,
            startDegrees, endDegrees, foreground);

        // Only the full sweep gets the trend: it is the one layout with rows to
        // spare, and on the others the reading has first call on them.
        drawReading(dc, centerX, (boxTop + boxBottom) / 2,
            2 * halfChord(inside, offset), boxBottom - boxTop, foreground, fullLens);
        return true;
    }

    //! The zoned band and its two markers, along an arc running from
    //! `startDegrees` at the shallow end to `endDegrees` at the deep end.
    private function drawArcBand(dc as Dc, centerX as Number, centerY as Number,
                                 bandRadius as Number, thickness as Number,
                                 startDegrees as Float, endDegrees as Float,
                                 foreground as Graphics.ColorType) as Void {
        var edges = zoneEdges();
        var scale = edges[edges.size() - 1];
        var direction = (endDegrees < startDegrees)
            ? Graphics.ARC_CLOCKWISE
            : Graphics.ARC_COUNTER_CLOCKWISE;

        // Rounded to whole degrees *before* the comparison, because those are
        // the values drawArc() is given and it treats an equal pair as a full
        // circle — a zone thinner than a degree would paint a ring right round
        // the display in its own colour rather than drawing nothing. Comparing
        // the Floats let a pair that differ by a fraction through to a call
        // where they no longer do.
        dc.setPenWidth(thickness);
        for (var i = 0; i < zone_colors.size(); i += 1) {
            var from = degreesFor(edges[i], scale, startDegrees, endDegrees).toNumber();
            var to = degreesFor(edges[i + 1], scale, startDegrees, endDegrees).toNumber();
            if (from == to) {
                continue; // A zone that rounds away to nothing.
            }
            dc.setColor(zone_colors[i], Graphics.COLOR_TRANSPARENT);
            dc.drawArc(centerX, centerY, bandRadius, direction,
                arcDegrees(from), arcDegrees(to));
        }
        dc.setPenWidth(1);

        // The session maximum, straight across the band rather than along it: a
        // short arc in another colour would just read as one more zone.
        var maximum = _model.max_depth;
        if (maximum != null && maximum > 0.0) {
            var angle = Math.toRadians(degreesFor(maximum, scale, startDegrees, endDegrees));
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
                degreesFor(depth, scale, startDegrees, endDegrees),
                markerHeight(thickness), markerHalfWidth(thickness));
        }
    }

    //! How far in from its ends the field's own edge forces the sweep, in
    //! degrees.
    //!
    //! The arc's ends sit on the lens's horizontal diameter, and a field often
    //! stops just short of it — a two-field top half is 129 rows tall on a 260
    //! row screen, one row shy. Pulling the sweep in by a degree keeps the whole
    //! scale on screen while the arc stays on the bezel. Shrinking the radius
    //! instead, which is what this used to do, costs half the gauge to save one
    //! row.
    private function sweepTrim(overshoot as Number, radius as Number) as Float {
        if (overshoot <= 0) {
            return 0.0;
        }
        if (overshoot >= radius) {
            return 90.0;
        }
        return Math.toDegrees(Math.asin(overshoot.toFloat() / radius)).toFloat();
    }

    //! A sweep angle wrapped into the 0-360 drawArc() expects.
    //!
    //! The full sweep runs from 225 degrees down past zero to -45, because
    //! degreesFor() interpolates along it and the marker trigonometry needs it
    //! monotonic. drawArc() takes the direction of travel as its own argument,
    //! so wrapping the endpoints here changes which pixels it paints not at all.
    private function arcDegrees(degrees as Number) as Number {
        var value = degrees % 360;
        return (value < 0) ? value + 360 : value;
    }

    //! Half the width of a circle of the given radius, `offset` rows from its
    //! centre.
    private function halfChord(radius as Number, offset as Number) as Number {
        var inside = radius * radius - offset * offset;
        return (inside <= 0) ? 0 : Math.sqrt(inside.toFloat()).toNumber();
    }

    //! The gauge as a bar along the bottom of the field with the reading above
    //! it, which is what every short, wide field gets.
    private function drawBarGauge(dc as Dc, foreground as Graphics.ColorType) as Void {
        var top = _layout.top();
        var bottom = _layout.bottom();

        var thickness = bandThickness(bottom - top, bar_thickness_percent, bar_max_thickness);
        var barTop = bottom - thickness - 1;

        // The span is asked for over the rows the marker reaches, not just the
        // rows of the bar, so nothing standing above it lands in the bezel.
        var bandTop = barTop - markerHeight(thickness);
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
                _layout.right(top, bottom) - _layout.left(top, bottom), bottom - top,
                foreground, false);
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
            var height = markerHeight(thickness);
            var halfWidth = markerHalfWidth(thickness);
            dc.fillPolygon([
                [depthX, barTop - 1],
                [depthX - halfWidth, barTop - 1 - height],
                [depthX + halfWidth, barTop - 1 - height],
            ] as Array<[Numeric, Numeric]>);
        }

        drawReading(dc, (left + right) / 2, (top + bandTop) / 2, barWidth, bandTop - top,
            foreground, false);
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
    private function bandThickness(available as Number, percent as Number,
                                   limit as Number) as Number {
        var thickness = available * percent / 100;
        if (thickness > limit) {
            return limit;
        }
        return (thickness < band_min_thickness) ? band_min_thickness : thickness;
    }

    //! How big the current-depth marker is, from the band it rides on.
    private function markerHeight(thickness as Number) as Number {
        var height = thickness * marker_height_percent / 100;
        return (height < marker_min_height) ? marker_min_height : height;
    }

    private function markerHalfWidth(thickness as Number) as Number {
        var halfWidth = thickness * marker_width_percent / 100;
        return (halfWidth < marker_min_half_width) ? marker_min_half_width : halfWidth;
    }

    //! An arrowhead pointing outwards along the arc's radius, its tip at
    //! `radius` and its base `height` further in.
    private function drawArrowhead(dc as Dc, centerX as Number, centerY as Number,
                                   radius as Number, degrees as Float,
                                   height as Number, halfWidth as Number) as Void {
        var angle = Math.toRadians(degrees);
        // The Dc measures angles anticlockwise from due east, but y grows
        // downwards, so the outward unit vector is (cos, -sin) on screen and
        // the one across it is (sin, cos).
        var out_x = Math.cos(angle);
        var out_y = -Math.sin(angle);
        var across_x = -out_y;
        var across_y = out_x;

        var baseRadius = radius - height;
        var baseX = centerX + baseRadius * out_x;
        var baseY = centerY + baseRadius * out_y;

        dc.fillPolygon([
            [(centerX + radius * out_x).toNumber(), (centerY + radius * out_y).toNumber()],
            [(baseX + halfWidth * across_x).toNumber(),
                (baseY + halfWidth * across_y).toNumber()],
            [(baseX - halfWidth * across_x).toNumber(),
                (baseY - halfWidth * across_y).toNumber()],
        ] as Array<[Numeric, Numeric]>);
    }

    //! The label, the reading, the session maximum, the trend where it was
    //! asked for, and the session totals where they fit — stacked and centred
    //! in the given box.
    //!
    //! The reading has first call on the space and the rest are dropped when
    //! what is left cannot hold them — a quarter-screen field cannot carry them
    //! all without all of them being useless, and the system has already shown
    //! the user the field's name on the screen they picked it from. Whether
    //! they fit is measured rather than guessed at, so a long translation drops
    //! its line instead of running off the side.
    private function drawReading(dc as Dc, centerX as Number, centerY as Number,
                                 boxWidth as Number, boxHeight as Number,
                                 foreground as Graphics.ColorType,
                                 withTrend as Boolean) as Void {
        var depth = _model.depth;
        var limited = _model.saturated;

        // The digits kept apart from everything that qualifies them, because a
        // numeric font holds digits and nothing else: the ">=", the unit and the
        // stale mark have to be drawn beside them in a text font. Joined again
        // for the text-font path, which renders the lot in one call.
        var number = _model.formatDepth(depth);
        var prefix = (limited && depth != null) ? ">=" : "";
        var suffix = (depth == null)
            ? ""
            : " " + _model.unitLabel() + _model.staleMark(depth);
        var text = prefix + number + suffix;

        var smallHeight = dc.getFontHeight(Graphics.FONT_XTINY);

        // Whether the totals are on the table at all. Tested before the reserve
        // below rather than after, because a field too small for them must not
        // reserve two rows it goes on to drop and shrink the reading to pay.
        var withStats = boxHeight >= stats_min_lines * smallHeight;

        // Leave room for every extra line that could be drawn if anything at
        // all fits that way, and give the reading the whole box when nothing
        // does. The count has to match what the block below can actually draw:
        // reserve two and draw three and a tall font overruns the box.
        var extraLines = 2 + (withTrend ? 1 : 0) + (withStats ? 2 : 0);
        var available = boxHeight - extraLines * smallHeight;

        // A numeric font first, and a text one only when none fits. They run
        // half again the height of the largest text font, which is what fills
        // the disc a full-screen arc leaves empty — fontFitting()'s list stops
        // at FONT_LARGE, and on a full screen that was the cap with rows still
        // to spare. The app's summary page already pays the same two-draw price
        // for them. Nothing to put in one when there is no reading: "n/a" has
        // no digits in it.
        var numberFont = (depth == null)
            ? null
            : numberFontFitting(dc, number,
                boxWidth - dc.getTextWidthInPixels(prefix + suffix, Graphics.FONT_XTINY),
                available);

        var font = Graphics.FONT_XTINY;
        if (numberFont != null) {
            font = numberFont;
        } else {
            font = _layout.fontFitting(dc, text, boxWidth, available);
            if (font == Graphics.FONT_XTINY) {
                font = _layout.fontFitting(dc, text, boxWidth, boxHeight);
            }
        }
        var lineHeight = dc.getFontHeight(font);
        var spare = boxHeight - lineHeight;

        var maximum = _model.max_depth;
        var maxText = (maximum == null)
            ? ""
            : _maxLabel + " " + _model.formatBounded(maximum, _model.saturation_seen)
                + " " + _model.unitLabel() + _model.staleMark(maximum);
        var showMax = (maxText.length() > 0) && (spare >= smallHeight)
            && (dc.getTextWidthInPixels(maxText, Graphics.FONT_XTINY) <= boxWidth);
        if (showMax) {
            spare -= smallHeight;
        }

        // A level trend draws nothing, so it also reserves nothing: the arrow
        // appears and disappears between rows that are there either way, which
        // is fine here because the rows around it are centred as a block rather
        // than pinned. That is the opposite of the app, where the indicator
        // sits inline and its slot has to be held open.
        var showTrend = withTrend && (_model.trend != DepthCore.TREND_LEVEL)
            && (spare >= smallHeight);
        if (showTrend) {
            spare -= smallHeight;
        }

        var showLabel = (spare >= smallHeight)
            && (dc.getTextWidthInPixels(_label, Graphics.FONT_XTINY) <= boxWidth);
        if (showLabel) {
            spare -= smallHeight;
        }

        // How the outing is going, under the maximum and in the same small
        // hand: this is a gauge, and the totals are context around the reading
        // rather than part of it.
        //
        // Both rows or neither. A dive count with no time under it reads as a
        // row that failed to draw rather than as a deliberate pair, and the two
        // answer half a question each.
        var divesText = _divesLabel + " " + _model.dive_count.format("%d");
        var bottomText = _bottomLabel + " " + DepthCore.formatDuration(_model.bottom_time);
        var showStats = withStats && (spare >= 2 * smallHeight)
            && (dc.getTextWidthInPixels(divesText, Graphics.FONT_XTINY) <= boxWidth)
            && (dc.getTextWidthInPixels(bottomText, Graphics.FONT_XTINY) <= boxWidth);

        var used = lineHeight + (showLabel ? smallHeight : 0) + (showMax ? smallHeight : 0)
            + (showTrend ? smallHeight : 0) + (showStats ? 2 * smallHeight : 0);
        var y = centerY - used / 2;

        if (showLabel) {
            dc.setColor(foreground, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, y, Graphics.FONT_XTINY, _label, Graphics.TEXT_JUSTIFY_CENTER);
            y += smallHeight;
        }

        var color = DepthCore.readingColor(depth, _model.color_profile, limited);
        if (numberFont != null) {
            drawNumberRow(dc, centerX, y, prefix, number, suffix, numberFont, color);
        } else {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        }
        y += lineHeight;

        if (showTrend) {
            drawTrendMark(dc, centerX, y + smallHeight / 2, smallHeight * 2 / 3);
            y += smallHeight;
        }

        if (showMax) {
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, y, Graphics.FONT_XTINY, maxText, Graphics.TEXT_JUSTIFY_CENTER);
            y += smallHeight;
        }

        if (showStats) {
            dc.setColor(foreground, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, y, Graphics.FONT_XTINY, divesText, Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(centerX, y + smallHeight, Graphics.FONT_XTINY, bottomText,
                Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    //! The largest numeric font that renders `digits` inside the given box, or
    //! null when none of them does.
    //!
    //! Kept here rather than folded into DepthFieldLayout.fontFitting(): that
    //! one is shared with Depth Chart, whose reading is short, wide and drawn in
    //! a single call, and it takes the whole string including the unit. Pulling
    //! the number out of its unit to buy a taller font is this field's own
    //! trade, worth making because its arc leaves it a tall box.
    private function numberFontFitting(dc as Dc, digits as String,
                                       availableWidth as Number,
                                       availableHeight as Number) as Graphics.FontType? {
        for (var i = 0; i < number_fonts.size(); i += 1) {
            if (dc.getFontHeight(number_fonts[i]) <= availableHeight
                && dc.getTextWidthInPixels(digits, number_fonts[i]) <= availableWidth) {
                return number_fonts[i];
            }
        }
        return null;
    }

    //! The reading on one row centred at `centerX`, with `y` its top: the number
    //! in a numeric font, and the ">=" and the unit that qualify it beside it in
    //! the small text font.
    //!
    //! The small parts are set on the number's bottom edge rather than its top,
    //! because the two fonts differ in height by more than the unit is tall and
    //! aligning their tops would leave it floating above the digits.
    //!
    //! One colour for all three. The app mutes its unit to grey, which works
    //! against the black it always draws on; a data field is handed white in day
    //! mode, where grey on white is what the system's own low-contrast text
    //! looks like just before it becomes unreadable.
    private function drawNumberRow(dc as Dc, centerX as Number, y as Number,
                                   prefix as String, number as String, suffix as String,
                                   numberFont as Graphics.FontType,
                                   color as Graphics.ColorType) as Void {
        var smallHeight = dc.getFontHeight(Graphics.FONT_XTINY);
        var prefixWidth = dc.getTextWidthInPixels(prefix, Graphics.FONT_XTINY);
        var numberWidth = dc.getTextWidthInPixels(number, numberFont);
        var suffixWidth = dc.getTextWidthInPixels(suffix, Graphics.FONT_XTINY);

        var smallY = y + dc.getFontHeight(numberFont) - smallHeight;
        var x = centerX - (prefixWidth + numberWidth + suffixWidth) / 2;

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (prefixWidth > 0) {
            dc.drawText(x, smallY, Graphics.FONT_XTINY, prefix, Graphics.TEXT_JUSTIFY_LEFT);
        }
        dc.drawText(x + prefixWidth, y, numberFont, number, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(x + prefixWidth + numberWidth, smallY, Graphics.FONT_XTINY, suffix,
            Graphics.TEXT_JUSTIFY_LEFT);
    }

    //! A triangle centred on (x, y) pointing the way the depth is going: red
    //! and down while descending, blue and up while ascending.
    //!
    //! Red for deeper and blue for shallower is the depth colour scale's own
    //! direction, and the same shapes and colours the app draws, because a
    //! reader should not have to learn the indicator twice. A polygon rather
    //! than an arrow character for the reason the ">=" is ASCII: the built-in
    //! fonts have patchy glyph coverage and would show empty boxes.
    //!
    //! Distinct from the arrowhead riding the band, which points outward along
    //! a radius and says *where* the reading is rather than which way it moves.
    private function drawTrendMark(dc as Dc, x as Number, y as Number, size as Number) as Void {
        var half = size / 2;
        if (_model.trend == DepthCore.TREND_DESCENDING) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([
                [x - half, y - half], [x + half, y - half], [x, y + half],
            ] as Array<[Numeric, Numeric]>);
        } else {
            dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([
                [x - half, y + half], [x + half, y + half], [x, y - half],
            ] as Array<[Numeric, Numeric]>);
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

    //! Where a depth sits along the sweep, in the Dc's degrees. Clamped to the
    //! ends: past full scale the marker pins at the deep end rather than
    //! wrapping round into the shallow one.
    private function degreesFor(meters as Float, scale as Float,
                                startDegrees as Float, endDegrees as Float) as Float {
        var fraction = meters / scale;
        if (fraction < 0.0) {
            fraction = 0.0;
        }
        if (fraction > 1.0) {
            fraction = 1.0;
        }
        return startDegrees + (endDegrees - startDegrees) * fraction;
    }
}
