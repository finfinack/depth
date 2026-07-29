import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

module DepthCore {

    //! Where a full DataField may safely draw, on a round screen as well as a
    //! rectangular one.
    //!
    //! A data field is handed a rectangle, but on a round watch part of that
    //! rectangle is off the lens: a field along the top edge has both its top
    //! corners cut away, and its topmost row is a single pixel wide. Code that
    //! draws to the full rectangle loses its label into the bezel — which is
    //! what the graph field used to do, and round is the shape that matters,
    //! since every device this ships to has one.
    //!
    //! Connect IQ gives a field two clues about its place on the screen and no
    //! more: the size of its rectangle, and getObscurityFlags(), which says
    //! which screen edges that rectangle touches. Between them those pin the
    //! origin down for most fields, and from the origin the lens is plain
    //! geometry. Not for all of them — see edgeOrigin() for the case they
    //! cannot settle and what that costs.
    //!
    //! Two things come out of that geometry, and drawing code needs both:
    //!
    //! - top() and bottom(), the rows worth drawing into at all. The pinched
    //!   ends of the lens are trimmed off, because a heading placed in a row
    //!   twenty pixels wide is a heading nobody reads.
    //! - left(from, to) and right(from, to), the horizontal span that is inside
    //!   the lens for every row of a band. A band low in the field is wider
    //!   than one at its top edge, so each piece of the drawing asks about its
    //!   own rows rather than sharing one inset.
    //!
    //! This is the only part of the barrel that draws anything. It lives here
    //! because the chart and the gauge are two apps with one layout, and a
    //! second copy of this geometry would drift from the first — the same
    //! reason the depth model is shared.
    class DepthFieldLayout {

        //! Kept between anything drawn and the edge of the lens, for the bezel
        //! and for the rounding in the row arithmetic below.
        const margin = 3;

        //! How much of the field's width a row has to keep to be worth drawing
        //! into. Rows narrower than this are trimmed off the top and the bottom
        //! of the field: they are the pinched ends of the lens.
        const usable_fraction = 0.6;

        //! ...and how far that trimming may eat into the field from either end,
        //! so a field that sits mostly under the bezel still draws something
        //! rather than collapsing to nothing.
        const trim_limit_fraction = 0.35;

        // The field, as the system handed it over.
        private var _width as Number = 0;
        private var _height as Number = 0;
        private var _obscurity as Number = -1;

        // ...and where that puts it on the screen.
        private var _originX as Number = 0;
        private var _originY as Number = 0;
        private var _centerX as Number = 0;
        private var _centerY as Number = 0;

        // Radius of the lens, already inset by the margin. Zero on a screen
        // that is not round, which switches the geometry off entirely.
        private var _radius as Float = 0.0;

        // The rows of the field left after trimming. Half-open, as row indices:
        // _bottom is one past the last row.
        private var _top as Number = 0;
        private var _bottom as Number = 0;

        //! Measure the field. Call this first thing in onUpdate(), which is the
        //! only place getObscurityFlags() is documented to be valid.
        function update(dc as Graphics.Dc, obscurity as Number) as Void {
            measure(dc.getWidth(), dc.getHeight(), obscurity);
        }

        //! update() with the field's size supplied, which is the only way the
        //! tests can put a field somewhere: the size comes from a Dc the caller
        //! does not get to choose, and every case worth checking here is about
        //! where on the screen the field lands. The same seam updateAt() gives
        //! the model, and for the same reason.
        //!
        //! Everything below is derived here rather than per call, because none
        //! of it changes while the field is on screen — the user cannot move a
        //! field mid-activity — and the row scan is not worth repeating at 1 Hz.
        function measure(width as Number, height as Number, obscurity as Number) as Void {
            if (width == _width && height == _height && obscurity == _obscurity) {
                return;
            }
            _width = width;
            _height = height;
            _obscurity = obscurity;

            var settings = System.getDeviceSettings();
            var screenWidth = settings.screenWidth;
            var screenHeight = settings.screenHeight;
            _centerX = screenWidth / 2;
            _centerY = screenHeight / 2;

            // Semi-round is a round screen with one edge flattened, so the
            // circle still describes it and errs towards drawing inside the
            // lens rather than outside it.
            var shape = settings.screenShape;
            var round = (shape == System.SCREEN_SHAPE_ROUND)
                || (shape == System.SCREEN_SHAPE_SEMI_ROUND);
            var shorter = (screenWidth < screenHeight) ? screenWidth : screenHeight;
            _radius = round ? (shorter / 2.0) - margin : 0.0;

            // The constants belong to DataField rather than to WatchUi itself,
            // and this class does not extend it — the chart and the gauge do —
            // so they are named in full.
            _originX = edgeOrigin(WatchUi.DataField.OBSCURE_LEFT,
                WatchUi.DataField.OBSCURE_RIGHT, screenWidth, width);
            _originY = edgeOrigin(WatchUi.DataField.OBSCURE_TOP,
                WatchUi.DataField.OBSCURE_BOTTOM, screenHeight, height);

            trimRows();
        }

        //! The size of the field, lens or no lens.
        function width() as Number {
            return _width;
        }

        function height() as Number {
            return _height;
        }

        //! The first row of the field worth drawing into, and one past the last.
        function top() as Number {
            return _top;
        }

        function bottom() as Number {
            return _bottom;
        }

        //! The leftmost and rightmost x that are inside the lens for every row
        //! of the band from `from` to `to`, so anything drawn between them is on
        //! screen for the whole band. `from` is inclusive and `to` exclusive, as
        //! top() and bottom() are.
        //!
        //! The lens narrows away from the middle of the screen, so the tightest
        //! row of a band is always one of its two ends.
        function left(from as Number, to as Number) as Number {
            if (_radius <= 0.0) {
                return margin;
            }
            var start = rowLeft(from);
            var end = rowLeft(lastRow(from, to));
            return (start > end) ? start : end;
        }

        function right(from as Number, to as Number) as Number {
            if (_radius <= 0.0) {
                return _width - margin;
            }
            var start = rowRight(from);
            var end = rowRight(lastRow(from, to));
            return (start < end) ? start : end;
        }

        //! The horizontal span of a single row, for drawing that follows the
        //! shape of the lens instead of squaring itself off inside it — the
        //! chart's trace, which would throw away most of a corner field if it
        //! had to fit a rectangle.
        //!
        //! Both round *inwards*, towards the middle of the lens. Truncating
        //! instead would move the left edge outwards by up to a pixel and hand
        //! back one that is fractionally off the lens, which is exactly the
        //! off-by-one this class exists to avoid. Rounding inwards is also what
        //! makes the row and column views agree at every point — see
        //! testColumnExtentAgreesWithTheRowSpan.
        function rowLeft(row as Number) as Number {
            if (_radius <= 0.0) {
                return margin;
            }
            var value = Math.ceil(_centerX - halfWidth(row) - _originX).toNumber();
            if (value < 0) {
                return 0;
            }
            return (value > _width) ? _width : value;
        }

        function rowRight(row as Number) as Number {
            if (_radius <= 0.0) {
                return _width - margin;
            }
            var value = Math.floor(_centerX + halfWidth(row) - _originX).toNumber();
            if (value > _width) {
                return _width;
            }
            return (value < 0) ? 0 : value;
        }

        //! The lens itself, in the field's own coordinates: its centre — which
        //! is usually outside the field — and its radius, already inset by the
        //! margin. The radius is 0 on a screen that is not round.
        //!
        //! Everything else here hands out rows and columns, because that is
        //! what drawing into a rectangle needs. The gauge does not draw into a
        //! rectangle: it draws an arc, and an arc concentric with the lens is
        //! on the lens at every point however large it is. Fitting it into a
        //! box inside the lens instead would shrink it to a fraction of the
        //! screen it could have used, so it gets the circle directly.
        function lensCenterX() as Number {
            return _centerX - _originX;
        }

        function lensCenterY() as Number {
            return _centerY - _originY;
        }

        function lensRadius() as Number {
            return _radius.toNumber();
        }

        //! The vertical extent of a single column, the same way round: what
        //! rowLeft()/rowRight() give a row, these give a column.
        //!
        //! The chart fills a solid body of water under its trace, one column at
        //! a time, and needs to know where each column enters and leaves the
        //! lens. Both round inwards, for the reason above.
        function columnTop(column as Number) as Number {
            if (_radius <= 0.0) {
                return 0;
            }
            var value = Math.ceil(_centerY - halfHeight(column) - _originY).toNumber();
            if (value < 0) {
                return 0;
            }
            return (value > _height) ? _height : value;
        }

        function columnBottom(column as Number) as Number {
            if (_radius <= 0.0) {
                return _height;
            }
            var value = Math.floor(_centerY + halfHeight(column) - _originY).toNumber();
            if (value > _height) {
                return _height;
            }
            return (value < 0) ? 0 : value;
        }

        //! The largest text font that renders `text` inside the given box.
        //!
        //! Both dimensions, because either one alone picks a font that does not
        //! fit: the chart's reading is short and wide, the gauge's has to sit
        //! inside an arc, and a font chosen on line height alone runs off the
        //! side of both. Pass an empty string to fit on height only.
        //!
        //! Text fonts rather than the numeric ones the app uses: those hold
        //! digits only, so they cannot render "n/a" or the unit, and a data
        //! field is too small for the size they buy to be worth two draws.
        function fontFitting(dc as Graphics.Dc, text as String,
                             availableWidth as Number, availableHeight as Number) as Graphics.FontType {
            var fonts = [
                Graphics.FONT_LARGE,
                Graphics.FONT_MEDIUM,
                Graphics.FONT_SMALL,
                Graphics.FONT_TINY,
            ] as Array<Graphics.FontType>;

            for (var i = 0; i < fonts.size(); i += 1) {
                if (dc.getFontHeight(fonts[i]) > availableHeight) {
                    continue;
                }
                if (text.length() == 0
                    || dc.getTextWidthInPixels(text, fonts[i]) <= availableWidth) {
                    return fonts[i];
                }
            }
            return Graphics.FONT_XTINY;
        }

        //! Where the field starts along one axis, from the screen edges it
        //! touches. A field touching the low edge starts at 0, one touching the
        //! high edge ends at the screen edge, and touching both is a field the
        //! full width or height of the screen, which also starts at 0.
        //!
        //! A field touching *neither* cannot be placed: it is somewhere in the
        //! middle and nothing here says where. Connect IQ exposes no way to ask
        //! a field its position, so this assumes centred, which is what a
        //! three-field layout does. Denser layouts stack their middle bands
        //! instead — checked against the layout rectangles the SDK ships per
        //! device, by as much as 2.8x the field's height.
        //!
        //! The error is bounded and one-directional: such a field believes the
        //! lens is wider than it is, so its outermost pixels can land under the
        //! bezel. It can never draw into another field, and it costs the chart
        //! and the gauge's bar their extreme corners on four-field-and-denser
        //! middle bands only. The gauge's arc is unaffected, since every layout
        //! that takes the arc touches the top or the bottom.
        private function edgeOrigin(low as Number, high as Number,
                                    screen as Number, size as Number) as Number {
            if ((_obscurity & low) != 0) {
                return 0;
            }
            if ((_obscurity & high) != 0) {
                return screen - size;
            }
            return (screen - size) / 2;
        }

        //! Trim the rows at the top and the bottom of the field where the lens
        //! has pinched in too far to draw into.
        private function trimRows() as Void {
            _top = 0;
            _bottom = _height;
            if (_radius <= 0.0) {
                return; // Rectangular screen: every row is usable.
            }

            var wanted = (_width * usable_fraction).toNumber();
            var limit = (_height * trim_limit_fraction).toNumber();

            while (_top < limit && (rowRight(_top) - rowLeft(_top)) < wanted) {
                _top += 1;
            }
            while (_bottom > _height - limit
                && (rowRight(_bottom - 1) - rowLeft(_bottom - 1)) < wanted) {
                _bottom -= 1;
            }
        }

        //! Half the width of the lens at the given row of the field, and half
        //! its height at the given column, both in pixels.
        private function halfWidth(row as Number) as Float {
            return halfChord(((_originY + row) - _centerY).toFloat());
        }

        private function halfHeight(column as Number) as Float {
            return halfChord(((_originX + column) - _centerX).toFloat());
        }

        //! Half the chord of the lens at the given distance from its centre.
        private function halfChord(offset as Float) as Float {
            var inside = _radius * _radius - offset * offset;
            // Math.sqrt() is declared as returning a Double.
            return (inside <= 0.0) ? 0.0 : Math.sqrt(inside).toFloat();
        }

        //! The last row of a half-open band, and the band's own row when it is
        //! empty — an empty band still has a position to be measured at.
        private function lastRow(from as Number, to as Number) as Number {
            return (to > from) ? to - 1 : from;
        }
    }
}
