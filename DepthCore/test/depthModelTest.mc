import Toybox.Activity;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

//! Tests for the parts of DepthModel that do not depend on elapsed time.
//!
//! update() reads System.getTimer() itself, so a test cannot make time pass:
//! two calls in a row are microseconds apart, which is exactly the case the
//! trend and the maximum both refuse to act on. Those are left to the
//! simulation in the commit history rather than pretended at here.
//!
//! What is covered is the arithmetic everything else rests on — the baseline,
//! the pressure-to-depth conversion, the floor at zero, and the formatting.
module DepthCore {

    // Salt water, where 1 m is exactly 10000 Pa, so the expected depths below
    // are exact rather than a rounding of 9806.65.
    const test_salt_pressure = 10000.0;
    const test_surface = 100000.0;

    // The helpers below carry no (:test): the runner turns every annotated
    // function into a test case of its own, whatever its name or signature.

    //! A model wired to salt water, whatever the settings say — the expected
    //! depths in the tests below depend on it.
    function saltWaterModel() as DepthModel {
        var model = new DepthModel();
        model.water_pressure = test_salt_pressure;
        model.unit = System.UNIT_METRIC;
        return model;
    }

    //! Feed a single raw pressure reading, in pascal, into the model.
    function readingAt(model as DepthModel, pascal as Float) as Void {
        var info = new Activity.Info();
        info.rawAmbientPressure = pascal;
        model.update(info);
    }

    //! Compare a reading against an expected value, tolerating float wobble.
    function assertClose(actual as Float?, expected as Float, message as String) as Void {
        Test.assertMessage(actual != null, message + ": expected a reading, got null");
        if (actual == null) {
            return;
        }
        var difference = actual - expected;
        if (difference < 0.0) {
            difference = -difference;
        }
        Test.assertMessage(difference < 0.001,
            message + ": got " + actual.format("%.4f") + ", expected " + expected.format("%.4f"));
    }

    (:test)
    function testFirstReadingBecomesTheSurface(logger as Logger) as Boolean {
        // With nothing to compare against, the first sample defines the surface
        // and so has to read as zero rather than as some absolute pressure.
        var model = saltWaterModel();
        readingAt(model, test_surface);
        assertClose(model.depth, 0.0, "first reading");
        return true;
    }

    (:test)
    function testDepthFromPressureAboveTheSurface(logger as Logger) as Boolean {
        var model = saltWaterModel();
        readingAt(model, test_surface);

        readingAt(model, test_surface + 10000.0);
        assertClose(model.depth, 1.0, "one metre");

        readingAt(model, test_surface + 200000.0);
        assertClose(model.depth, 20.0, "twenty metres");
        return true;
    }

    (:test)
    function testWaterTypeChangesTheConversion(logger as Logger) as Boolean {
        // The same pressure is a different depth in fresh water, and getting
        // this backwards is a silent 2% error rather than a visible failure.
        var model = saltWaterModel();
        model.water_pressure = 9806.65;
        readingAt(model, test_surface);
        readingAt(model, test_surface + 9806.65);
        assertClose(model.depth, 1.0, "one metre of fresh water");
        return true;
    }

    (:test)
    function testDepthNeverGoesNegative(logger as Logger) as Boolean {
        // Pressure below the baseline means the baseline is too high — walking
        // uphill, or weather. It must read as the surface, not as a negative.
        var model = saltWaterModel();
        readingAt(model, test_surface);
        readingAt(model, test_surface - 5000.0);
        assertClose(model.depth, 0.0, "above the baseline");
        return true;
    }

    (:test)
    function testNoPressureReadsAsUnknown(logger as Logger) as Boolean {
        // Not zero. A watch with no barometer reading is not at the surface.
        var model = saltWaterModel();
        readingAt(model, test_surface);
        readingAt(model, test_surface + 10000.0);

        var info = new Activity.Info();
        info.rawAmbientPressure = null;
        info.ambientPressure = null;
        model.update(info);

        Test.assertMessage(model.depth == null, "depth without a pressure reading");
        Test.assertEqual(model.trend, TREND_LEVEL);
        return true;
    }

    (:test)
    function testFallsBackToSmoothedPressure(logger as Logger) as Boolean {
        // rawAmbientPressure is preferred, but is not populated everywhere.
        var model = saltWaterModel();

        var info = new Activity.Info();
        info.rawAmbientPressure = null;
        info.ambientPressure = test_surface;
        model.update(info);

        info.ambientPressure = test_surface + 10000.0;
        model.update(info);
        assertClose(model.depth, 1.0, "one metre from the fallback");
        return true;
    }

    (:test)
    function testRezeroForgetsEverything(logger as Logger) as Boolean {
        var model = saltWaterModel();
        readingAt(model, test_surface);
        readingAt(model, test_surface + 10000.0);

        model.rezero();

        Test.assertMessage(model.depth == null, "depth after a re-zero");
        Test.assertMessage(model.max_depth == null, "maximum after a re-zero");
        Test.assertMessage(model.pressure == null, "pressure after a re-zero");
        Test.assertEqual(model.trend, TREND_LEVEL);

        // The next reading defines a new surface, wherever it is.
        readingAt(model, test_surface + 50000.0);
        assertClose(model.depth, 0.0, "surface after re-zero");
        return true;
    }

    (:test)
    function testExposesTheRawPressure(logger as Logger) as Boolean {
        // This is what gets recorded into the FIT file, so it has to be the
        // sensor reading itself and not anything derived from it.
        var model = saltWaterModel();
        readingAt(model, test_surface + 12345.0);
        assertClose(model.pressure, test_surface + 12345.0, "raw pressure");
        return true;
    }

    (:test)
    function testFormatDepthMetric(logger as Logger) as Boolean {
        var model = saltWaterModel();
        Test.assertEqual(model.formatDepth(0.0), "0.00");
        Test.assertEqual(model.formatDepth(1.5), "1.50");
        Test.assertEqual(model.formatDepth(12.345), "12.35");
        Test.assertEqual(model.unitLabel(), "m");
        return true;
    }

    (:test)
    function testFormatDepthStatute(logger as Logger) as Boolean {
        var model = saltWaterModel();
        model.unit = System.UNIT_STATUTE;
        // One metre is 3.28084 ft, shown to one decimal.
        Test.assertEqual(model.formatDepth(1.0), "3.3");
        Test.assertEqual(model.formatDepth(10.0), "32.8");
        Test.assertEqual(model.unitLabel(), "ft");
        return true;
    }

    (:test)
    function testFormatDepthWithNoReading(logger as Logger) as Boolean {
        var model = saltWaterModel();
        Test.assertEqual(model.formatDepth(null), "n/a");
        model.unit = System.UNIT_STATUTE;
        Test.assertEqual(model.formatDepth(null), "n/a");
        return true;
    }
}
