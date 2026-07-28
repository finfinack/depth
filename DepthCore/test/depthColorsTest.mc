import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Test;

//! Tests for the depth colour scale.
//!
//! Only the boundaries are interesting: the thresholds are in metres whatever
//! the display unit is, and an off-by-one on a comparison would put a whole
//! band on the wrong colour without anything else noticing.
module DepthCore {

    //! Check one profile's three boundaries at once. Each threshold belongs to
    //! the deeper band, so the value just below it is still the shallower
    //! colour — that inclusive-upward rule is what these are really pinning.
    function assertBands(profile as Number, green as Float, yellow as Float, red as Float) as Void {
        var margin = 0.001;
        Test.assertEqual(depthColor(0.0, profile), Graphics.COLOR_BLUE);
        Test.assertEqual(depthColor(green - margin, profile), Graphics.COLOR_BLUE);
        Test.assertEqual(depthColor(green, profile), Graphics.COLOR_GREEN);
        Test.assertEqual(depthColor(yellow - margin, profile), Graphics.COLOR_GREEN);
        Test.assertEqual(depthColor(yellow, profile), Graphics.COLOR_YELLOW);
        Test.assertEqual(depthColor(red - margin, profile), Graphics.COLOR_YELLOW);
        Test.assertEqual(depthColor(red, profile), Graphics.COLOR_RED);
        Test.assertEqual(depthColor(red * 10.0, profile), Graphics.COLOR_RED);
    }

    (:test)
    function testDepthColorHasNoReading(logger as Logger) as Boolean {
        Test.assertEqual(depthColor(null, PROFILE_SNORKEL), Graphics.COLOR_LT_GRAY);
        Test.assertEqual(depthColor(null, PROFILE_DEEP), Graphics.COLOR_LT_GRAY);
        return true;
    }

    (:test)
    function testSnorkelBands(logger as Logger) as Boolean {
        assertBands(PROFILE_SNORKEL, 2.0, 5.0, 10.0);
        return true;
    }

    (:test)
    function testFreediveBands(logger as Logger) as Boolean {
        assertBands(PROFILE_FREEDIVE, 10.0, 20.0, 30.0);
        return true;
    }

    (:test)
    function testDeepBands(logger as Logger) as Boolean {
        assertBands(PROFILE_DEEP, 20.0, 40.0, 60.0);
        return true;
    }

    (:test)
    function testUnknownProfileFallsBackToSnorkel(logger as Logger) as Boolean {
        // A stored setting from a future version, or a hand-edited one. It has
        // to land on a scale rather than on no scale at all.
        assertBands(-1, 2.0, 5.0, 10.0);
        assertBands(99, 2.0, 5.0, 10.0);
        return true;
    }
}
