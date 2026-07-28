import Toybox.Lang;
import Toybox.System;
import Toybox.Test;
import Toybox.WatchUi;

//! Tests for the round-screen field layout.
//!
//! These run against whatever device the test build targets, so they assert
//! relationships rather than pixel values: that a field along the top edge
//! gives up rows the lens has pinched away, that a field in the middle of the
//! screen gives up none, that nothing is ever offered outside the field, and
//! that a band low in a field is wider than one at its top edge. Hard-coded
//! coordinates would only be true on one watch.
//!
//! The one number they do assume is the screen shape, which is read from the
//! device and branched on: every product this ships to is round, but a test
//! that silently passed on a rectangular one would be worth nothing.
module DepthCore {

    //! Whether the device under test has a lens that cuts the corners off.
    function screenIsRound() as Boolean {
        var shape = System.getDeviceSettings().screenShape;
        return (shape == System.SCREEN_SHAPE_ROUND)
            || (shape == System.SCREEN_SHAPE_SEMI_ROUND);
    }

    //! A field of the given size in the given place, measured and ready to ask.
    function layoutFor(width as Number, height as Number, obscurity as Number) as DepthFieldLayout {
        var layout = new DepthFieldLayout();
        layout.measure(width, height, obscurity);
        return layout;
    }

    //! A full-width band along the top edge, as in a two- or three-field layout.
    function topField() as DepthFieldLayout {
        var settings = System.getDeviceSettings();
        return layoutFor(settings.screenWidth, settings.screenHeight / 3,
            WatchUi.DataField.OBSCURE_TOP | WatchUi.DataField.OBSCURE_LEFT
                | WatchUi.DataField.OBSCURE_RIGHT);
    }

    //! The middle band of the same layout, which touches no horizon at all
    //! except the two sides.
    function middleField() as DepthFieldLayout {
        var settings = System.getDeviceSettings();
        return layoutFor(settings.screenWidth, settings.screenHeight / 3,
            WatchUi.DataField.OBSCURE_LEFT | WatchUi.DataField.OBSCURE_RIGHT);
    }

    (:test)
    function testFieldKeepsItsOwnSize(logger as Logger) as Boolean {
        var layout = layoutFor(120, 60, WatchUi.DataField.OBSCURE_TOP);
        Test.assertEqual(layout.width(), 120);
        Test.assertEqual(layout.height(), 60);
        return true;
    }

    //! The bug this whole class exists for: drawing at row 0 of a top field puts
    //! it in the bezel, because the topmost row of the lens is a pixel wide.
    (:test)
    function testTopFieldGivesUpItsPinchedRows(logger as Logger) as Boolean {
        var layout = topField();
        if (!screenIsRound()) {
            Test.assertEqual(layout.top(), 0);
            return true;
        }
        Test.assert(layout.top() > 0);
        Test.assertEqual(layout.bottom(), layout.height());
        return true;
    }

    //! ...and the other half of it: a field across the middle of the screen is
    //! entirely on the lens, so trimming it would throw away good rows.
    (:test)
    function testMiddleFieldGivesUpNothing(logger as Logger) as Boolean {
        var layout = middleField();
        Test.assertEqual(layout.top(), 0);
        Test.assertEqual(layout.bottom(), layout.height());
        return true;
    }

    //! However far the lens pinches in, something is always left to draw into.
    //! A field that measured itself down to nothing would just go blank.
    (:test)
    function testTrimmingAlwaysLeavesRows(logger as Logger) as Boolean {
        var layout = topField();
        Test.assert(layout.bottom() > layout.top());
        return true;
    }

    //! The span is inside the field, always. Anything else is a draw call off
    //! the edge of the buffer.
    (:test)
    function testSpanStaysInsideTheField(logger as Logger) as Boolean {
        var layout = topField();
        var top = layout.top();
        var bottom = layout.bottom();
        Test.assert(layout.left(top, bottom) >= 0);
        Test.assert(layout.right(top, bottom) <= layout.width());
        Test.assert(layout.left(top, bottom) < layout.right(top, bottom));
        return true;
    }

    //! A band low in a top field is further from the bezel than one at its top
    //! edge, so it has more room. This is why each piece of the drawing asks
    //! about its own rows instead of sharing one inset with the rest.
    (:test)
    function testLowerBandsAreWider(logger as Logger) as Boolean {
        var layout = topField();
        var top = layout.top();
        var bottom = layout.bottom();
        var band = (bottom - top) / 3;
        if (band < 2) {
            return true; // Too short to have an "upper" and a "lower" at all.
        }

        var upper = layout.right(top, top + band) - layout.left(top, top + band);
        var lower = layout.right(bottom - band, bottom) - layout.left(bottom - band, bottom);
        if (!screenIsRound()) {
            Test.assertEqual(upper, lower);
            return true;
        }
        Test.assert(lower > upper);
        return true;
    }

    //! A band is only as wide as its narrowest row, or something drawn across
    //! the whole of it leaves the lens partway down.
    (:test)
    function testBandIsNoWiderThanItsNarrowestRow(logger as Logger) as Boolean {
        var layout = topField();
        var top = layout.top();
        var bottom = layout.bottom();

        for (var row = top; row < bottom; row += 1) {
            Test.assert(layout.left(top, bottom) >= layout.rowLeft(row));
            Test.assert(layout.right(top, bottom) <= layout.rowRight(row));
        }
        return true;
    }

    //! contains() is the cheap per-point form of rowLeft()/rowRight(), and the
    //! chart trusts it once per pixel column. The two have to agree.
    (:test)
    function testContainsAgreesWithTheRowSpan(logger as Logger) as Boolean {
        var layout = middleField();

        for (var row = layout.top(); row < layout.bottom(); row += 7) {
            var left = layout.rowLeft(row);
            var right = layout.rowRight(row);
            Test.assert(layout.contains(left, row));
            Test.assert(layout.contains(right - 1, row));
            if (left > 0) {
                Test.assert(!layout.contains(left - 1, row));
            }
            if (right < layout.width()) {
                Test.assert(!layout.contains(right + 1, row));
            }
        }
        return true;
    }

    //! columnTop()/columnBottom() are rowLeft()/rowRight() turned ninety
    //! degrees, and the chart fills a column of water between them. They have
    //! to agree with contains() the same way the row pair does.
    (:test)
    function testColumnExtentAgreesWithContains(logger as Logger) as Boolean {
        var layout = middleField();

        for (var x = 0; x < layout.width(); x += 11) {
            var columnTop = layout.columnTop(x);
            var columnBottom = layout.columnBottom(x);
            Test.assert(columnTop >= 0);
            Test.assert(columnBottom <= layout.height());
            if (columnTop >= columnBottom) {
                continue; // This column misses the lens entirely.
            }

            Test.assert(layout.contains(x, columnTop));
            Test.assert(layout.contains(x, columnBottom - 1));
            if (columnTop > 0) {
                Test.assert(!layout.contains(x, columnTop - 1));
            }
            if (columnBottom < layout.height()) {
                Test.assert(!layout.contains(x, columnBottom + 1));
            }
        }
        return true;
    }

    //! A column in the middle of a field reaches further than one at its edge,
    //! which is what gives the filled chart its lens shape.
    (:test)
    function testMiddleColumnsAreTaller(logger as Logger) as Boolean {
        var layout = topField();
        var middle = layout.columnBottom(layout.width() / 2) - layout.columnTop(layout.width() / 2);
        var edge = layout.columnBottom(0) - layout.columnTop(0);

        if (!screenIsRound()) {
            Test.assertEqual(middle, edge);
            return true;
        }
        Test.assert(middle > edge);
        return true;
    }

    //! A corner field is the tightest case there is: two of its edges are the
    //! screen's, so the lens cuts diagonally across it.
    (:test)
    function testCornerFieldStaysOnTheLens(logger as Logger) as Boolean {
        var settings = System.getDeviceSettings();
        var layout = layoutFor(settings.screenWidth / 2, settings.screenHeight / 4,
            WatchUi.DataField.OBSCURE_BOTTOM | WatchUi.DataField.OBSCURE_LEFT);

        Test.assert(layout.bottom() > layout.top());
        for (var row = layout.top(); row < layout.bottom(); row += 1) {
            Test.assert(layout.rowLeft(row) >= 0);
            Test.assert(layout.rowRight(row) <= layout.width());
            Test.assert(layout.rowLeft(row) <= layout.rowRight(row));
        }

        // The bottom-left corner of a round screen is bezel, so the field's own
        // left edge cannot be usable all the way down.
        if (screenIsRound()) {
            Test.assert(layout.rowLeft(layout.bottom() - 1) > 0);
        }
        return true;
    }

    //! Measuring is skipped when nothing moved, so a second call with the same
    //! field must not disturb what the first one worked out.
    (:test)
    function testRemeasuringIsStable(logger as Logger) as Boolean {
        var layout = topField();
        var top = layout.top();
        var bottom = layout.bottom();
        var left = layout.left(top, bottom);

        layout.measure(layout.width(), layout.height(),
            WatchUi.DataField.OBSCURE_TOP | WatchUi.DataField.OBSCURE_LEFT
                | WatchUi.DataField.OBSCURE_RIGHT);

        Test.assertEqual(layout.top(), top);
        Test.assertEqual(layout.bottom(), bottom);
        Test.assertEqual(layout.left(top, bottom), left);
        return true;
    }

    //! ...but a field that really has moved has to be measured again, or it
    //! keeps drawing to where it used to be.
    (:test)
    function testMovingTheFieldRemeasuresIt(logger as Logger) as Boolean {
        var settings = System.getDeviceSettings();
        var width = settings.screenWidth;
        var height = settings.screenHeight / 3;

        var layout = layoutFor(width, height,
            WatchUi.DataField.OBSCURE_TOP | WatchUi.DataField.OBSCURE_LEFT
                | WatchUi.DataField.OBSCURE_RIGHT);
        var trimmed = layout.top();

        layout.measure(width, height,
            WatchUi.DataField.OBSCURE_LEFT | WatchUi.DataField.OBSCURE_RIGHT);

        Test.assertEqual(layout.top(), 0);
        if (screenIsRound()) {
            Test.assert(trimmed > 0);
        }
        return true;
    }
}
