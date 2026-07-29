import Toybox.Lang;
import Toybox.Test;

//! Tests for the FIT conversions.
//!
//! These carry the most risk of anything in the barrel. A wrong colour is
//! visible immediately; a wrong conversion here is written into the activity
//! and looks entirely plausible forever after, so the clamps are worth pinning
//! down exactly.
module DepthCore {

    (:test)
    function testDepthCentimetersConvertsMetres(logger as Logger) as Boolean {
        Test.assertEqual(depthCentimeters(0.0), 0);
        Test.assertEqual(depthCentimeters(1.0), 100);
        Test.assertEqual(depthCentimeters(12.34), 1234);
        Test.assertEqual(depthCentimeters(655.0), 65500);
        return true;
    }

    (:test)
    function testDepthCentimetersRounds(logger as Logger) as Boolean {
        // Half a centimetre rounds up, just under it rounds down.
        Test.assertEqual(depthCentimeters(0.005), 1);
        Test.assertEqual(depthCentimeters(0.004), 0);
        Test.assertEqual(depthCentimeters(1.005), 101);
        return true;
    }

    (:test)
    function testDepthCentimetersHasNoReading(logger as Logger) as Boolean {
        // Null is "no pressure yet", not "at the surface", but 0 is the only
        // thing a UINT16 can say about it.
        Test.assertEqual(depthCentimeters(null), 0);
        return true;
    }

    (:test)
    function testDepthCentimetersFloorsAtZero(logger as Logger) as Boolean {
        // The model clamps depth at zero, but a negative here would wrap to a
        // huge positive in an unsigned field rather than reading as shallow.
        Test.assertEqual(depthCentimeters(-0.01), 0);
        Test.assertEqual(depthCentimeters(-100.0), 0);
        return true;
    }

    (:test)
    function testDepthCentimetersClampsToUint16(logger as Logger) as Boolean {
        Test.assertEqual(depthCentimeters(655.35), fit_depth_max);
        Test.assertEqual(depthCentimeters(700.0), fit_depth_max);
        // Just under the ceiling still converts rather than clamping, so the
        // clamp cannot be quietly swallowing a whole range of real values.
        Test.assertEqual(depthCentimeters(655.33), 65533);
        return true;
    }

    (:test)
    function testDepthCentimetersNeverRecordsTheInvalidMarker(logger as Logger) as Boolean {
        // 0xFFFF is the FIT profile's "no reading" marker for a uint16, so
        // clamping to it would file garbage as *absent* rather than as pinned
        // at the ceiling — the opposite of what the clamp exists for, and
        // invisible afterwards because the sample simply would not be there.
        Test.assertMessage(fit_depth_max < fit_uint16_invalid,
            "the ceiling has to sit below the invalid marker");

        var absurd = [655.35, 700.0, 1.0e9, 1.0e20] as Array<Float>;
        for (var i = 0; i < absurd.size(); i += 1) {
            Test.assertMessage(depthCentimeters(absurd[i]) != fit_uint16_invalid,
                "recorded the invalid marker for " + absurd[i].format("%.2f"));
        }
        return true;
    }

    (:test)
    function testDepthCentimetersSurvivesAbsurdInput(logger as Logger) as Boolean {
        // The reason the clamp compares before converting. A value this size
        // overflows a signed 32-bit Number, so clamping after .toNumber() would
        // wrap it into something small and believable instead of pinning it.
        Test.assertEqual(depthCentimeters(1.0e9), fit_depth_max);
        Test.assertEqual(depthCentimeters(1.0e20), fit_depth_max);
        return true;
    }

    (:test)
    function testPressurePascalsConverts(logger as Logger) as Boolean {
        Test.assertEqual(pressurePascals(0.0), 0);
        Test.assertEqual(pressurePascals(101325.0), 101325);
        // Sea level pressure plus about a metre of water, the range that
        // matters most for whether the sensor saturates.
        Test.assertEqual(pressurePascals(111325.0), 111325);
        return true;
    }

    (:test)
    function testPressurePascalsHasNoReading(logger as Logger) as Boolean {
        Test.assertEqual(pressurePascals(null), 0);
        Test.assertEqual(pressurePascals(-1.0), 0);
        return true;
    }

    (:test)
    function testPressurePascalsSurvivesAbsurdInput(logger as Logger) as Boolean {
        Test.assertEqual(pressurePascals(3000000.0), fit_pressure_max);
        Test.assertEqual(pressurePascals(1.0e20), fit_pressure_max);
        return true;
    }
}
