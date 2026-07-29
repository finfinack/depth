import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import DepthCore;

//! The zoned ring the app draws around the reading on the current-depth page:
//! the colour profile's four bands as a 270 degree scale, with the current
//! depth riding it as an arrowhead and the session maximum crossing it as a
//! tick. The same gauge the Depth Gauge data field draws on a full-screen
//! layout, and read the same way — see that field's README for why the two
//! markers are different shapes and why the scale runs one zone past red.
//!
//! **Deliberately a second copy rather than shared code.** Almost everything
//! that makes `depth_gaugeView` long — obscurity flags, the bar fallback,
//! trimming the sweep to a field that stops short of the lens diameter, and
//! deciding between all of them — is there because a data field is handed a
//! rectangle it does not choose. The app always owns the whole round screen, so
//! the centre is the screen's centre and the sweep is always the full 270
//! degrees; what is left after dropping the rest is this file. Folding the two
//! together belongs in the barrel and is worth doing, but only once the field's
//! 270 degree path has been seen on a watch — until then a shared version would
//! put the app's weight on code nobody has watched run.
class depthRing {

    // Thickness of the coloured band, as a share of the screen's radius. The
    // ceiling stops a large display turning the ring into a doughnut and the
    // floor keeps the colours readable on a small one.
    const band_thickness_percent = 16;
    const band_max_thickness = 34;
    const band_min_thickness = 5;

    // The arrowhead that rides the band at the current depth, sized from the
    // band rather than fixed so it stays in proportion on every display.
    const marker_height_percent = 90;
    const marker_width_percent = 65;
    const marker_min_height = 6;
    const marker_min_half_width = 5;

    // Below this there is no room left inside the ring for the reading, so the
    // ring is dropped rather than drawn over the number.
    const min_inside_radius = 40;

    // 270 degrees with the gap at the bottom, the way a speedometer runs and
    // the way the watch's own zone gauges do. 225 degrees is lower-left and -45
    // lower-right; clockwise between them passes over the top, so shallow is on
    // the left and the four zones get half again the angular resolution a half
    // sweep would give them.
    //
    // The end runs past zero into negative degrees on purpose: degreesFor() and
    // the marker trigonometry both need the sweep monotonic, and drawArc() gets
    // its own wrapped copy from arcDegrees().
    const sweep_start = 225.0;
    const sweep_end = -45.0;

    // Shallow to deep. The boundaries between them are the colour profile's
    // own, so the ring and the reading cannot disagree about a depth.
    const zone_colors = [
        Graphics.COLOR_BLUE,
        Graphics.COLOR_GREEN,
        Graphics.COLOR_YELLOW,
        Graphics.COLOR_RED,
    ] as Array<Graphics.ColorType>;

    private var _model as DepthModel;

    function initialize(model as DepthModel) {
        _model = model;
    }

    //! Draw the ring concentric with the display. Does nothing if what is left
    //! inside it would be too small to hold the reading.
    //!
    //! Concentric with the screen rather than fitted into a box: a circle on the
    //! display's own centre is on the display at every point, so the band can
    //! run right along the bezel and leave the whole middle to the number.
    function draw(dc as Dc, width as Number, height as Number) as Void {
        var centerX = width / 2;
        var centerY = height / 2;
        var radius = (width < height) ? centerX : centerY;

        var thickness = bandThickness(radius);

        // drawArc strokes on both sides of the radius it is given, so the band
        // is pulled in by half its thickness to keep its outer edge on the arc.
        var bandRadius = radius - thickness / 2;
        var inside = bandRadius - thickness / 2;
        if (inside < min_inside_radius) {
            return;
        }

        var edges = zoneEdges();
        var scale = edges[edges.size() - 1];

        // Rounded to whole degrees *before* the comparison, because those are
        // the values drawArc() is given and it treats an equal pair as a full
        // circle — a zone thinner than a degree would paint a ring right round
        // the display in its own colour rather than drawing nothing.
        dc.setPenWidth(thickness);
        for (var i = 0; i < zone_colors.size(); i += 1) {
            var from = degreesFor(edges[i], scale).toNumber();
            var to = degreesFor(edges[i + 1], scale).toNumber();
            if (from == to) {
                continue; // A zone that rounds away to nothing.
            }
            dc.setColor(zone_colors[i], Graphics.COLOR_TRANSPARENT);
            dc.drawArc(centerX, centerY, bandRadius, Graphics.ARC_CLOCKWISE,
                arcDegrees(from), arcDegrees(to));
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
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            drawArrowhead(dc, centerX, centerY, bandRadius - thickness / 2 - 1,
                degreesFor(depth, scale), markerHeight(thickness),
                markerHalfWidth(thickness));
        }
    }

    //! The five depths bounding the four zones, shallow to deep.
    //!
    //! Full scale is one zone-width past the red boundary rather than at it:
    //! ending there would leave the last zone infinitely thin, and a gauge that
    //! pins the moment it turns red says nothing after that.
    private function zoneEdges() as Array<Float> {
        var bands = DepthCore.profileBands(_model.color_profile);
        return [0.0, bands[0], bands[1], bands[2], bands[2] + (bands[2] - bands[1])]
            as Array<Float>;
    }

    //! Where a depth sits along the sweep, in the Dc's degrees. Clamped to the
    //! ends: past full scale the marker pins at the deep end rather than
    //! wrapping round into the shallow one.
    private function degreesFor(meters as Float, scale as Float) as Float {
        var fraction = meters / scale;
        if (fraction < 0.0) {
            fraction = 0.0;
        }
        if (fraction > 1.0) {
            fraction = 1.0;
        }
        return sweep_start + (sweep_end - sweep_start) * fraction;
    }

    //! A sweep angle wrapped into the 0-360 drawArc() expects. The sweep runs
    //! past zero into negative degrees so it stays monotonic; drawArc() takes
    //! its direction of travel as a separate argument, so wrapping the
    //! endpoints changes which pixels it paints not at all.
    private function arcDegrees(degrees as Number) as Number {
        var value = degrees % 360;
        return (value < 0) ? value + 360 : value;
    }

    private function bandThickness(radius as Number) as Number {
        var thickness = radius * band_thickness_percent / 100;
        if (thickness > band_max_thickness) {
            return band_max_thickness;
        }
        return (thickness < band_min_thickness) ? band_min_thickness : thickness;
    }

    private function markerHeight(thickness as Number) as Number {
        var height = thickness * marker_height_percent / 100;
        return (height < marker_min_height) ? marker_min_height : height;
    }

    private function markerHalfWidth(thickness as Number) as Number {
        var halfWidth = thickness * marker_width_percent / 100;
        return (halfWidth < marker_min_half_width) ? marker_min_half_width : halfWidth;
    }

    //! An arrowhead pointing outwards along the ring's radius, its tip at
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
}
