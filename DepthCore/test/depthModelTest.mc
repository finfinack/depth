import Toybox.Activity;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

//! Tests for DepthModel.
//!
//! Everything here goes through updateAt(), which is update() with the clock
//! supplied. Every interval the model cares about is minutes long, so a test
//! that could not move the clock could only ever reach the arithmetic — the
//! baseline window, the submerged watchdog, the trend hysteresis and the
//! two-sample maximum are the parts that carry the risk, and all four are about
//! elapsed time.
//!
//! Timestamps below are milliseconds, as System.getTimer() reports them, and
//! samples are one second apart because that is roughly the rate the pressure
//! sensor updates at and the rate the widget polls it.
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

    //! Feed a single raw pressure reading, in pascal, taken at `at` milliseconds.
    function readingAt(model as DepthModel, pascal as Float, at as Number) as Void {
        var info = new Activity.Info();
        info.rawAmbientPressure = pascal;
        model.updateAt(info, at);
    }

    //! Feed a reading a given depth below the surface used throughout, so the
    //! tests below read as the dive profile they describe.
    function diveTo(model as DepthModel, meters as Float, at as Number) as Void {
        readingAt(model, test_surface + meters * test_salt_pressure, at);
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
        readingAt(model, test_surface, 0);
        assertClose(model.depth, 0.0, "first reading");
        return true;
    }

    (:test)
    function testDepthFromPressureAboveTheSurface(logger as Logger) as Boolean {
        var model = saltWaterModel();
        readingAt(model, test_surface, 0);

        readingAt(model, test_surface + 10000.0, 1000);
        assertClose(model.depth, 1.0, "one metre");

        readingAt(model, test_surface + 200000.0, 2000);
        assertClose(model.depth, 20.0, "twenty metres");
        return true;
    }

    (:test)
    function testWaterTypeChangesTheConversion(logger as Logger) as Boolean {
        // The same pressure is a different depth in fresh water, and getting
        // this backwards is a silent 2% error rather than a visible failure.
        var model = saltWaterModel();
        model.water_pressure = 9806.65;
        readingAt(model, test_surface, 0);
        readingAt(model, test_surface + 9806.65, 1000);
        assertClose(model.depth, 1.0, "one metre of fresh water");
        return true;
    }

    (:test)
    function testDepthNeverGoesNegative(logger as Logger) as Boolean {
        // Pressure below the baseline means the baseline is too high — walking
        // uphill, or weather. It must read as the surface, not as a negative.
        var model = saltWaterModel();
        readingAt(model, test_surface, 0);
        readingAt(model, test_surface - 5000.0, 1000);
        assertClose(model.depth, 0.0, "above the baseline");
        return true;
    }

    (:test)
    function testNoPressureReadsAsUnknown(logger as Logger) as Boolean {
        // Not zero. A watch with no barometer reading is not at the surface.
        var model = saltWaterModel();
        readingAt(model, test_surface, 0);
        readingAt(model, test_surface + 10000.0, 1000);

        var info = new Activity.Info();
        info.rawAmbientPressure = null;
        info.ambientPressure = null;
        model.updateAt(info, 2000);

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
        model.updateAt(info, 0);

        info.ambientPressure = test_surface + 10000.0;
        model.updateAt(info, 1000);
        assertClose(model.depth, 1.0, "one metre from the fallback");
        return true;
    }

    (:test)
    function testRezeroForgetsEverything(logger as Logger) as Boolean {
        var model = saltWaterModel();
        readingAt(model, test_surface, 0);
        readingAt(model, test_surface + 10000.0, 1000);

        model.rezero();

        Test.assertMessage(model.depth == null, "depth after a re-zero");
        Test.assertMessage(model.max_depth == null, "maximum after a re-zero");
        Test.assertMessage(model.pressure == null, "pressure after a re-zero");
        Test.assertEqual(model.trend, TREND_LEVEL);

        // The next reading defines a new surface, wherever it is.
        readingAt(model, test_surface + 50000.0, 2000);
        assertClose(model.depth, 0.0, "surface after re-zero");
        return true;
    }

    (:test)
    function testExposesTheRawPressure(logger as Logger) as Boolean {
        // This is what gets recorded into the FIT file, so it has to be the
        // sensor reading itself and not anything derived from it.
        var model = saltWaterModel();
        readingAt(model, test_surface + 12345.0, 0);
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

    (:test)
    function testUndeclaredSettingFallsBackToItsDefault(logger as Logger) as Boolean {
        // test/resources/settings/properties.xml deliberately leaves
        // colorProfile out, the way the two data fields do. Properties.getValue()
        // throws on a key the app never declared, so constructing the model at
        // all is half of what this asserts; landing on the default is the rest.
        var model = new DepthModel();
        Test.assertEqual(model.color_profile, PROFILE_SNORKEL);
        return true;
    }

    //
    // The maximum. It is confirmed by two consecutive samples, so that a single
    // noisy spike cannot latch into a value that then never goes away.
    //

    (:test)
    function testMaximumNeedsTwoSamples(logger as Logger) as Boolean {
        var model = saltWaterModel();
        diveTo(model, 0.0, 0);
        Test.assertMessage(model.max_depth == null, "maximum from a single sample");

        // The pair (0 m, 1 m) only confirms the shallower of the two.
        diveTo(model, 1.0, 1000);
        assertClose(model.max_depth, 0.0, "maximum after one deep sample");

        diveTo(model, 1.0, 2000);
        assertClose(model.max_depth, 1.0, "maximum after two deep samples");
        return true;
    }

    (:test)
    function testUnconfirmedSpikeDoesNotBecomeTheMaximum(logger as Logger) as Boolean {
        // A plausible descent rate, so the rate guard lets it through — the
        // two-sample confirmation is the only thing standing in its way.
        var model = saltWaterModel();
        diveTo(model, 0.0, 0);
        diveTo(model, 1.0, 1000);
        diveTo(model, 1.0, 2000);

        diveTo(model, 3.0, 3000);
        diveTo(model, 1.0, 4000);
        assertClose(model.max_depth, 1.0, "maximum after an unconfirmed spike");
        return true;
    }

    (:test)
    function testImpossibleDescentDoesNotBecomeTheMaximum(logger as Logger) as Boolean {
        // 9 m in one second is three times the fastest descent treated as real,
        // so it is a sensor glitch and must not reach the maximum at all.
        var model = saltWaterModel();
        diveTo(model, 0.0, 0);
        diveTo(model, 1.0, 1000);
        diveTo(model, 1.0, 2000);

        diveTo(model, 10.0, 3000);
        assertClose(model.max_depth, 1.0, "maximum after an impossible descent");

        diveTo(model, 1.0, 4000);
        assertClose(model.max_depth, 1.0, "maximum once the glitch has passed");
        return true;
    }

    //
    // The trend. The rate behind it is smoothed, so it lags the depth on
    // purpose, and it commits and releases at two different thresholds.
    //

    (:test)
    function testTrendCommitsWhileDescending(logger as Logger) as Boolean {
        var model = saltWaterModel();
        diveTo(model, 0.0, 0);
        Test.assertEqual(model.trend, TREND_LEVEL); // A rate needs two samples.

        // 1 m/s, which the smoothing turns into a rate of 0.30 m/s — past the
        // 0.15 m/s the trend commits at.
        diveTo(model, 1.0, 1000);
        Test.assertEqual(model.trend, TREND_DESCENDING);
        return true;
    }

    (:test)
    function testTrendHoldsBetweenTheThresholds(logger as Logger) as Boolean {
        // The point of the two thresholds: a rate that has fallen below the one
        // the trend commits at, but not yet to the one it releases at, holds the
        // direction it had. With a single threshold the indicator would chatter
        // every time the rate grazed it.
        var model = saltWaterModel();
        diveTo(model, 0.0, 0);
        diveTo(model, 1.0, 1000);
        Test.assertEqual(model.trend, TREND_DESCENDING); // rate 0.300

        diveTo(model, 1.0, 2000); // rate 0.210, still past the commit threshold
        diveTo(model, 1.0, 3000); // rate 0.147, between the two thresholds
        Test.assertEqual(model.trend, TREND_DESCENDING);

        diveTo(model, 1.0, 4000); // rate 0.103, still between them
        Test.assertEqual(model.trend, TREND_DESCENDING);

        diveTo(model, 1.0, 5000); // rate 0.072, below the release threshold
        Test.assertEqual(model.trend, TREND_LEVEL);
        return true;
    }

    (:test)
    function testTrendTurnsAroundOnAscent(logger as Logger) as Boolean {
        var model = saltWaterModel();
        diveTo(model, 0.0, 0);
        diveTo(model, 1.0, 1000);
        diveTo(model, 2.0, 2000);
        diveTo(model, 3.0, 3000); // rate 0.657
        Test.assertEqual(model.trend, TREND_DESCENDING);

        // One second of ascent is not enough to pull the smoothed rate back
        // through the threshold, and the indicator is supposed to lag rather
        // than flip on a single sample.
        diveTo(model, 2.0, 4000); // rate 0.160
        Test.assertEqual(model.trend, TREND_DESCENDING);

        diveTo(model, 1.0, 5000); // rate -0.188
        Test.assertEqual(model.trend, TREND_ASCENDING);
        return true;
    }

    //
    // The baseline window. It is trailing rather than a ratcheting minimum, so
    // a low sample has to age out of it, and frozen while submerged, so a dive
    // cannot drag it down.
    //

    (:test)
    function testWindowKeepsTheOlderBucketButNotForever(logger as Logger) as Boolean {
        // The surface pressure rises by 500 Pa — 5 cm of water, well inside the
        // surface band, so every sample here counts as being at the surface.
        var model = saltWaterModel();
        readingAt(model, test_surface, 0);

        readingAt(model, test_surface + 500.0, 1000);
        assertClose(model.depth, 0.05, "while the old minimum is current");

        // One bucket length on, the old minimum is in the older half of the
        // window and still counts.
        readingAt(model, test_surface + 500.0, 100000);
        assertClose(model.depth, 0.05, "one rotation later");

        // Two, and it has aged out: the surface is now where the watch is.
        readingAt(model, test_surface + 500.0, 200000);
        assertClose(model.depth, 0.0, "two rotations later");
        return true;
    }

    (:test)
    function testWindowDropsBothHalvesAfterALongGap(logger as Logger) as Boolean {
        // More than a full window between samples, which is what surfacing from
        // a long dive looks like. Both halves are stale, so neither survives.
        var model = saltWaterModel();
        readingAt(model, test_surface, 0);
        readingAt(model, test_surface + 500.0, 200000);
        assertClose(model.depth, 0.0, "after a full window of silence");
        return true;
    }

    (:test)
    function testCounterWrapRotatesTheWindow(logger as Logger) as Boolean {
        // System.getTimer() wraps. Treating the negative interval as a rotation
        // is what keeps the window from freezing on its contents forever.
        var model = saltWaterModel();
        readingAt(model, test_surface, 1000);
        readingAt(model, test_surface + 500.0, 500);
        assertClose(model.depth, 0.0, "after the counter wrapped");
        return true;
    }

    (:test)
    function testBaselineIsFrozenWhileSubmerged(logger as Logger) as Boolean {
        // Eight minutes at 5 m. If the window were still being fed, the dive
        // would drag the baseline down after it and the depth would decay
        // towards zero on its own.
        var model = saltWaterModel();
        diveTo(model, 0.0, 0);
        diveTo(model, 5.0, 1000);
        diveTo(model, 5.0, 480000);
        assertClose(model.depth, 5.0, "eight minutes down");
        return true;
    }

    (:test)
    function testSubmergedWatchdogStartsOver(logger as Logger) as Boolean {
        // Past ten minutes the baseline is likelier to be wrong than the depth
        // to be real, so the model starts over from the current pressure. Note
        // what this costs: a genuine dive that long reads as the surface.
        var model = saltWaterModel();
        diveTo(model, 0.0, 0);
        diveTo(model, 5.0, 1000);

        diveTo(model, 5.0, 601000);
        assertClose(model.depth, 5.0, "just inside the watchdog");

        diveTo(model, 5.0, 601001);
        assertClose(model.depth, 0.0, "once the watchdog has fired");
        return true;
    }
}
