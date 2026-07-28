import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Test;

//! Tests for the depth colour scale.
//!
//! Only the boundaries are interesting: the thresholds are in metres whatever
//! the display unit is, and an off-by-one on a comparison would put a whole
//! band on the wrong colour without anything else noticing.
module DepthCore {

    (:test)
    function testDepthColorHasNoReading(logger as Logger) as Boolean {
        Test.assertEqual(depthColor(null), Graphics.COLOR_LT_GRAY);
        return true;
    }

    (:test)
    function testDepthColorBands(logger as Logger) as Boolean {
        Test.assertEqual(depthColor(0.0), Graphics.COLOR_BLUE);
        Test.assertEqual(depthColor(5.0), Graphics.COLOR_BLUE);
        Test.assertEqual(depthColor(15.0), Graphics.COLOR_GREEN);
        Test.assertEqual(depthColor(25.0), Graphics.COLOR_YELLOW);
        Test.assertEqual(depthColor(100.0), Graphics.COLOR_RED);
        return true;
    }

    (:test)
    function testDepthColorBoundariesAreInclusiveUpward(logger as Logger) as Boolean {
        // Each threshold belongs to the deeper band.
        Test.assertEqual(depthColor(9.999), Graphics.COLOR_BLUE);
        Test.assertEqual(depthColor(10.0), Graphics.COLOR_GREEN);

        Test.assertEqual(depthColor(19.999), Graphics.COLOR_GREEN);
        Test.assertEqual(depthColor(20.0), Graphics.COLOR_YELLOW);

        Test.assertEqual(depthColor(29.999), Graphics.COLOR_YELLOW);
        Test.assertEqual(depthColor(30.0), Graphics.COLOR_RED);
        return true;
    }
}
