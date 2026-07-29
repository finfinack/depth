import Toybox.Activity;
import Toybox.Application;
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
        var model = new DepthModel(REZERO_HANDLE);
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

    //! Whether the one-shot re-zero trigger is still waiting to be acted on.
    function rezeroPending() as Boolean {
        var value = Application.Properties.getValue("rezero");
        return (value instanceof Lang.Boolean) ? value : false;
    }

    (:test)
    function testOnlyTheHandlingModelConsumesTheRezeroTrigger(logger as Logger) as Boolean {
        // The trigger is one-shot, and switching it off is what consuming it
        // means. An app with a glance builds two models against one property
        // store, so a model built for a view that is thrown away after every
        // draw has to leave the trigger for the one the user is looking at —
        // otherwise the setting silently does nothing.
        Application.Properties.setValue("rezero", true);

        var ignored = new DepthModel(REZERO_IGNORE);
        Test.assertMessage(rezeroPending(),
            "the trigger survived a model that does not handle it");

        var handler = new DepthModel(REZERO_HANDLE);
        Test.assertMessage(!rezeroPending(),
            "the trigger was consumed by the model that does handle it");

        // The flag governs the trigger and nothing else: both models read the
        // rest of the settings identically.
        Test.assertEqual(ignored.color_profile, handler.color_profile);
        Test.assertEqual(ignored.water_pressure, handler.water_pressure);
        return true;
    }

    (:test)
    function testUndeclaredSettingFallsBackToItsDefault(logger as Logger) as Boolean {
        // test/resources/settings/properties.xml deliberately leaves
        // colorProfile out, the way the two data fields do. Properties.getValue()
        // throws on a key the app never declared, so constructing the model at
        // all is half of what this asserts; landing on the default is the rest.
        var model = new DepthModel(REZERO_HANDLE);
        Test.assertEqual(model.color_profile, PROFILE_SNORKEL);
        return true;
    }

    //
    // The maximum. A sample is accepted as a new maximum when it is no deeper
    // than the descent leading into it explains — which keeps a real peak
    // exactly, where judging each pair on its own used to shave a full sample
    // of descent rate off every one of them.
    //

    (:test)
    function testMaximumKeepsTheRealPeak(logger as Logger) as Boolean {
        // The bug this rule exists for. A dive to 3 m turning round at 1 m/s
        // has to record 3 m: keeping the shallower of each consecutive pair
        // recorded 2.5 m, a metre-a-second under-report at every turn, and
        // reading shallower than the diver went is the dangerous direction.
        var model = saltWaterModel();
        diveTo(model, 0.0, 0);
        diveTo(model, 0.5, 1000);
        diveTo(model, 1.5, 2000);
        diveTo(model, 2.5, 3000);
        diveTo(model, 3.0, 4000); // The turn.
        assertClose(model.max_depth, 3.0, "maximum at the peak");

        diveTo(model, 2.0, 5000);
        assertClose(model.max_depth, 3.0, "maximum on the way back up");
        return true;
    }

    (:test)
    function testMaximumNeedsARunInToJudgeAgainst(logger as Logger) as Boolean {
        var model = saltWaterModel();
        diveTo(model, 0.0, 0);
        Test.assertMessage(model.max_depth == null, "maximum from a single sample");

        // A metre in the first second, with nothing behind it to say whether a
        // descent was under way. Held back rather than trusted — which costs
        // nothing, because a diver who is really going down goes on doing it.
        diveTo(model, 1.0, 1000);
        Test.assertMessage(model.max_depth == null, "maximum with no run-in");

        diveTo(model, 1.0, 2000);
        assertClose(model.max_depth, 1.0, "maximum once the descent is established");
        return true;
    }

    (:test)
    function testSpikeOutOfALevelSeriesIsNotTheMaximum(logger as Logger) as Boolean {
        // 2 m in one second from a series going nowhere. It is inside
        // max_descent_rate, so the rate guard alone lets it through — the
        // run-in is what rejects it.
        var model = saltWaterModel();
        diveTo(model, 0.0, 0);
        diveTo(model, 1.0, 1000);
        diveTo(model, 1.0, 2000);

        diveTo(model, 3.0, 3000);
        assertClose(model.max_depth, 1.0, "maximum during the spike");

        diveTo(model, 1.0, 4000);
        assertClose(model.max_depth, 1.0, "maximum after the spike");
        return true;
    }

    (:test)
    function testSpikeAtTheRateLimitIsNotTheMaximum(logger as Logger) as Boolean {
        // Exactly max_descent_rate, which the rate guard compares with a strict
        // greater-than and therefore does not catch. This is the case the old
        // pair rule caught and a bare rate guard would not, so the run-in has
        // to catch it instead.
        var model = saltWaterModel();
        diveTo(model, 0.0, 0);
        diveTo(model, 1.0, 1000);
        diveTo(model, 1.0, 2000);

        diveTo(model, 4.0, 3000);
        assertClose(model.max_depth, 1.0, "maximum after a spike at the rate limit");
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

    (:test)
    function testFastDescentIsNotMistakenForASpike(logger as Logger) as Boolean {
        // 2 m/s sustained is a real freedive descent, not a glitch, and the
        // maximum has to follow it down rather than stalling at the first
        // sample the run-in had not yet caught up with.
        var model = saltWaterModel();
        diveTo(model, 0.0, 0);
        diveTo(model, 2.0, 1000);
        diveTo(model, 4.0, 2000);
        diveTo(model, 6.0, 3000);
        assertClose(model.max_depth, 6.0, "maximum during a fast descent");
        return true;
    }

    //
    // The raw maximum. It takes every sample as it came, so the true peak is
    // bracketed between it and max_depth. Recorded into the FIT file and shown
    // nowhere.
    //

    (:test)
    function testRawMaximumTakesEverySample(logger as Logger) as Boolean {
        var model = saltWaterModel();
        diveTo(model, 0.0, 0);
        assertClose(model.max_depth_raw, 0.0, "raw maximum from the first sample");
        diveTo(model, 0.0, 1000);

        // A spike out of a level series, which the confirmed maximum rejects.
        diveTo(model, 3.0, 2000);
        assertClose(model.max_depth_raw, 3.0, "raw maximum after a spike");
        assertClose(model.max_depth, 0.0, "confirmed maximum ignored the spike");

        // ...and an impossible descent, which it also rejects.
        diveTo(model, 20.0, 3000);
        assertClose(model.max_depth_raw, 20.0, "raw maximum after an impossible descent");
        assertClose(model.max_depth, 0.0, "confirmed maximum ignored that too");
        return true;
    }

    (:test)
    function testRezeroForgetsBothMaximums(logger as Logger) as Boolean {
        var model = saltWaterModel();
        diveTo(model, 0.0, 0);
        diveTo(model, 1.0, 1000);
        diveTo(model, 1.0, 2000);

        model.rezero();
        Test.assertMessage(model.max_depth == null, "maximum after a re-zero");
        Test.assertMessage(model.max_depth_raw == null, "raw maximum after a re-zero");
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
    // Sensor saturation. A watch barometer stops rising somewhere past a metre
    // or so of water, and the reading then understates the depth without
    // anything else going wrong — the one failure mode that misleads instead of
    // alarming, so the detection is worth pinning exactly.
    //

    //! Hold the pressure at a fixed depth for `count` samples, one second
    //! apart, starting at `at` — what a pinned sensor looks like. Returns the
    //! time after the last one.
    function holdAt(model as DepthModel, meters as Float, at as Number,
                    count as Number) as Number {
        var now = at;
        for (var i = 0; i < count; i += 1) {
            diveTo(model, meters, now);
            now += 1000;
        }
        return now;
    }

    (:test)
    function testFlatPressureAtDepthReadsAsSaturated(logger as Logger) as Boolean {
        var model = saltWaterModel();
        diveTo(model, 0.0, 0);
        Test.assertMessage(!model.saturated, "saturated at the surface");

        // Eight identical samples at 6.4 m — roughly where the fenix firmware
        // is reported to stop.
        holdAt(model, 6.4, 1000, 9);
        Test.assertMessage(model.saturated, "eight flat samples at depth");
        Test.assertMessage(model.saturation_seen, "the session has seen it");
        return true;
    }

    (:test)
    function testShortFlatRunIsNotSaturation(logger as Logger) as Boolean {
        // Holding still for a moment is not a pinned sensor. The run has to be
        // long enough that a live barometer would have jittered.
        var model = saltWaterModel();
        diveTo(model, 0.0, 0);
        holdAt(model, 6.4, 1000, 4);
        Test.assertMessage(!model.saturated, "four flat samples");
        return true;
    }

    (:test)
    function testFlatPressureAtTheSurfaceIsNotSaturation(logger as Logger) as Boolean {
        // A watch sitting still on a table reads flat forever, and says nothing
        // about the sensor's ceiling.
        var model = saltWaterModel();
        holdAt(model, 0.0, 0, 30);
        Test.assertMessage(!model.saturated, "flat at the surface");
        Test.assertMessage(!model.saturation_seen, "and never seen");
        return true;
    }

    (:test)
    function testMovingPressureClearsSaturation(logger as Logger) as Boolean {
        // Coming back up under the ceiling, the sensor starts tracking again
        // and the live reading has to be trusted again straight away.
        var model = saltWaterModel();
        diveTo(model, 0.0, 0);
        var now = holdAt(model, 6.4, 1000, 9);
        Test.assertMessage(model.saturated, "pinned");

        diveTo(model, 3.0, now);
        Test.assertMessage(!model.saturated, "after the pressure moved again");
        // ...but the maximum was reached while pinned, so it stays bounded.
        Test.assertMessage(model.saturation_seen, "the session still remembers");
        return true;
    }

    (:test)
    function testNoReadingClearsSaturation(logger as Logger) as Boolean {
        var model = saltWaterModel();
        diveTo(model, 0.0, 0);
        var now = holdAt(model, 6.4, 1000, 9);
        Test.assertMessage(model.saturated, "pinned");

        var info = new Activity.Info();
        info.rawAmbientPressure = null;
        info.ambientPressure = null;
        model.updateAt(info, now);
        Test.assertMessage(!model.saturated, "a reading that is not there is not pinned");
        return true;
    }

    (:test)
    function testRezeroForgetsSaturation(logger as Logger) as Boolean {
        var model = saltWaterModel();
        diveTo(model, 0.0, 0);
        holdAt(model, 6.4, 1000, 9);

        model.rezero();
        Test.assertMessage(!model.saturated, "saturated after a re-zero");
        Test.assertMessage(!model.saturation_seen, "seen after a re-zero");
        return true;
    }

    (:test)
    function testFormatBoundedMarksALowerBound(logger as Logger) as Boolean {
        // ASCII ">=", not "≥": the built-in fonts have patchy glyph coverage.
        var model = saltWaterModel();
        Test.assertEqual(model.formatBounded(6.4, true), ">=6.40");
        Test.assertEqual(model.formatBounded(6.4, false), "6.40");
        // There is nothing to bound when there is no reading.
        Test.assertEqual(model.formatBounded(null, true), "n/a");
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
    function testALoneLowSampleStaysOutOfTheWindow(logger as Logger) as Boolean {
        // What the max-of-pairs prefilter is for. One spuriously low reading
        // must not become the surface, or every depth after it reads deeper
        // than it is until the sample ages out.
        var model = saltWaterModel();
        readingAt(model, test_surface, 0);
        readingAt(model, test_surface, 1000);
        readingAt(model, test_surface - 1000.0, 2000); // The outlier.
        readingAt(model, test_surface, 3000);

        // 1 m down. Against the true surface that is 1.00; had the outlier got
        // into the window it would read 1.10.
        diveTo(model, 1.0, 4000);
        assertClose(model.depth, 1.0, "depth after a lone low sample");
        return true;
    }

    (:test)
    function testSurfacingDoesNotAnchorTheBaselineAtDepth(logger as Logger) as Boolean {
        // The other half of that prefilter: only a previous sample that was
        // itself at the surface may stand in for one. Surfacing from a
        // submersion longer than a full window rotates the window empty, so a
        // submerged previous sample would be the only value left in it — and
        // the next descent would then read 0.00 at depth, with the baseline
        // pinned there. Exactly the silent under-read the watchdog was removed
        // for, arriving by another route.
        var model = saltWaterModel();
        diveTo(model, 0.0, 0);
        diveTo(model, 5.0, 1000);

        // Five minutes down, so both halves of the window are stale.
        diveTo(model, 5.0, 300000);

        // Up for one sample, then straight back down.
        diveTo(model, 0.0, 301000);
        assertClose(model.depth, 0.0, "at the surface");

        diveTo(model, 5.0, 302000);
        assertClose(model.depth, 5.0, "back down after a single surface sample");
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
    function testLongSubmersionWarnsButDoesNotRezero(logger as Logger) as Boolean {
        // Past ten minutes the baseline is likelier to be wrong than the depth
        // real — but the reading does not move. Re-zeroing here used to make
        // the watch read 0.00 while submerged, which is indistinguishable from
        // a watch that is working and understates every reading after it.
        var model = saltWaterModel();
        diveTo(model, 0.0, 0);
        diveTo(model, 5.0, 1000);

        diveTo(model, 5.0, 601000);
        assertClose(model.depth, 5.0, "just inside the warning");
        Test.assertMessage(!model.baseline_stale, "not yet suspect");

        diveTo(model, 5.0, 601001);
        assertClose(model.depth, 5.0, "the depth is left alone");
        Test.assertMessage(model.baseline_stale, "the baseline is called suspect");
        return true;
    }

    (:test)
    function testSurfacingClearsTheStaleBaseline(logger as Logger) as Boolean {
        // Back inside the surface band the window is being fed again, so
        // whatever the baseline was, it is being measured rather than guessed.
        var model = saltWaterModel();
        diveTo(model, 0.0, 0);
        diveTo(model, 5.0, 1000);
        diveTo(model, 5.0, 601001);
        Test.assertMessage(model.baseline_stale, "suspect while down");

        diveTo(model, 0.0, 602000);
        Test.assertMessage(!model.baseline_stale, "cleared on surfacing");
        return true;
    }

    (:test)
    function testBriefSurfacingRestartsTheClock(logger as Logger) as Boolean {
        // The ten minutes have to be unbroken. One sample inside the surface
        // band is enough to start them over, which is why a snorkeller whose
        // wrist keeps breaking the surface never reaches the warning.
        var model = saltWaterModel();
        diveTo(model, 0.0, 0);
        diveTo(model, 5.0, 1000);

        diveTo(model, 0.0, 300000);
        diveTo(model, 5.0, 301000);

        diveTo(model, 5.0, 601001); // Ten minutes after the *first* descent.
        Test.assertMessage(!model.baseline_stale, "the clock restarted");
        return true;
    }

    (:test)
    function testStaleMarksBothReadings(logger as Logger) as Boolean {
        // The baseline is what both the depth and the maximum are measured
        // from, so a suspect one makes both suspect. No reading gets no mark.
        var model = saltWaterModel();
        Test.assertEqual(model.staleMark(1.0), "");

        diveTo(model, 0.0, 0);
        diveTo(model, 5.0, 1000);
        diveTo(model, 5.0, 601001);
        Test.assertEqual(model.staleMark(model.depth), "?");
        Test.assertEqual(model.staleMark(model.max_depth), "?");
        Test.assertEqual(model.staleMark(null), "");
        return true;
    }

    (:test)
    function testSensorGapDoesNotMakeNeighboursOfDistantSamples(logger as Logger) as Boolean {
        // Two readings either side of a dropout are not consecutive samples,
        // and judging the second against the first would let a maximum through
        // on a run-in that never happened.
        var model = saltWaterModel();
        diveTo(model, 0.0, 0);
        diveTo(model, 1.0, 1000);
        diveTo(model, 1.0, 2000);
        assertClose(model.max_depth, 1.0, "maximum before the gap");

        var info = new Activity.Info();
        info.rawAmbientPressure = null;
        info.ambientPressure = null;
        model.updateAt(info, 3000);

        // Straight back to 3 m. With the pre-gap sample still in place this
        // would have had a run-in to justify it; on its own it does not.
        diveTo(model, 3.0, 4000);
        assertClose(model.max_depth, 1.0, "maximum is not judged across the gap");
        return true;
    }

    //! A model at the surface with a known dive threshold, ready to be dived.
    //! Returns the time of the next sample.
    function surfacedModel(model as DepthModel) as Number {
        model.dive_threshold = 1.0;
        diveTo(model, 0.0, 0);
        return 1000;
    }

    (:test)
    function testGoingPastTheThresholdCountsOneDive(logger as Logger) as Boolean {
        var model = saltWaterModel();
        var now = surfacedModel(model);

        Test.assertMessage(model.dive_count == 0, "no dive before going under");
        now = holdAt(model, 2.0, now, 3);
        Test.assertMessage(model.dive_count == 1,
            "one dive, got " + model.dive_count);

        // Surfacing does not count a second one.
        holdAt(model, 0.0, now, 3);
        Test.assertMessage(model.dive_count == 1,
            "still one dive after surfacing, got " + model.dive_count);
        return true;
    }

    (:test)
    function testADiveIsCountedWhileItIsStillUnderWay(logger as Logger) as Boolean {
        // The count goes up on the way down, not on the way back up, so what a
        // diver sees does not jump the moment they surface.
        var model = saltWaterModel();
        var now = surfacedModel(model);

        diveTo(model, 1.5, now);
        Test.assertMessage(model.dive_count == 1,
            "counted as it starts, got " + model.dive_count);
        return true;
    }

    (:test)
    function testHoveringOnTheThresholdIsStillOneDive(logger as Logger) as Boolean {
        // The whole point of the release being lower than the threshold: a
        // diver sitting right on 1 m must not score a dive per sample.
        var model = saltWaterModel();
        var now = surfacedModel(model);

        for (var i = 0; i < 6; i += 1) {
            diveTo(model, 1.1, now);
            now += 1000;
            diveTo(model, 0.9, now);
            now += 1000;
        }
        Test.assertMessage(model.dive_count == 1,
            "grazing the threshold is one dive, got " + model.dive_count);
        return true;
    }

    (:test)
    function testComingUpPastTheReleaseStartsANewDive(logger as Logger) as Boolean {
        var model = saltWaterModel();
        var now = surfacedModel(model);

        now = holdAt(model, 2.0, now, 2);
        now = holdAt(model, 0.2, now, 2); // Clear of the 0.5 m release.
        holdAt(model, 2.0, now, 2);
        Test.assertMessage(model.dive_count == 2,
            "two separate dives, got " + model.dive_count);
        return true;
    }

    (:test)
    function testStayingShallowIsNotADive(logger as Logger) as Boolean {
        var model = saltWaterModel();
        var now = surfacedModel(model);

        holdAt(model, 0.8, now, 10);
        Test.assertMessage(model.dive_count == 0,
            "above the threshold is no dive, got " + model.dive_count);
        Test.assertMessage(model.bottom_time == 0,
            "and no bottom time, got " + model.bottom_time);
        return true;
    }

    (:test)
    function testBottomTimeCountsFromTheSampleThatStartsTheDive(logger as Logger) as Boolean {
        var model = saltWaterModel();
        var now = surfacedModel(model);

        // Four samples a second apart: the first starts the dive and is not
        // itself an interval, so three intervals are counted.
        holdAt(model, 2.0, now, 4);
        Test.assertMessage(model.bottom_time == 3000,
            "three seconds of bottom time, got " + model.bottom_time);
        return true;
    }

    (:test)
    function testBottomTimeStopsWhenTheDiveDoes(logger as Logger) as Boolean {
        var model = saltWaterModel();
        var now = surfacedModel(model);

        now = holdAt(model, 2.0, now, 3); // Two intervals below.
        holdAt(model, 0.1, now, 5);       // The first of these ends the dive.
        Test.assertMessage(model.bottom_time == 3000,
            "time at the surface is not bottom time, got " + model.bottom_time);
        return true;
    }

    (:test)
    function testBottomTimeIsNotCountedAcrossASensorGap(logger as Logger) as Boolean {
        // Readings stop for two minutes while submerged. The watch cannot know
        // it was down there the whole time, so it must not claim it was.
        var model = saltWaterModel();
        var now = surfacedModel(model);

        now = holdAt(model, 2.0, now, 2); // One interval, 1000 ms.
        diveTo(model, 2.0, now + 120000);
        Test.assertMessage(model.bottom_time == 1000,
            "the gap is not bottom time, got " + model.bottom_time);
        return true;
    }

    (:test)
    function testBottomTimeIgnoresAWrappedClock(logger as Logger) as Boolean {
        // System.getTimer() wraps. An interval that measures negative cannot be
        // measured at all, so it is dropped rather than added or subtracted.
        var model = saltWaterModel();
        var now = surfacedModel(model);

        now = holdAt(model, 2.0, now, 2);
        diveTo(model, 2.0, 5); // The counter has wrapped round to near zero.
        Test.assertMessage(model.bottom_time == 1000,
            "a backwards interval is dropped, got " + model.bottom_time);

        // And the model keeps counting from the new clock rather than sulking.
        diveTo(model, 2.0, 1005);
        Test.assertMessage(model.bottom_time == 2000,
            "counting resumes after the wrap, got " + model.bottom_time);
        return true;
    }

    (:test)
    function testRezeroForgetsDivesAndBottomTime(logger as Logger) as Boolean {
        var model = saltWaterModel();
        var now = surfacedModel(model);

        holdAt(model, 2.0, now, 4);
        Test.assertMessage(model.dive_count == 1 && model.bottom_time == 3000,
            "there was a dive to forget");

        model.rezero();
        Test.assertMessage(model.dive_count == 0,
            "dives forgotten, got " + model.dive_count);
        Test.assertMessage(model.bottom_time == 0,
            "bottom time forgotten, got " + model.bottom_time);
        return true;
    }

    (:test)
    function testDiveThresholdIsClampedToSomethingUsable(logger as Logger) as Boolean {
        // The value comes from outside the app. Zero would make every sample a
        // dive and the count run away, so it is held to a usable range rather
        // than trusted.
        var model = saltWaterModel();

        Properties.setValue("diveThreshold", 0);
        model.loadSettings();
        assertClose(model.dive_threshold, model.min_dive_threshold,
            "a zero threshold is clamped up");

        Properties.setValue("diveThreshold", 1000000);
        model.loadSettings();
        assertClose(model.dive_threshold, model.max_dive_threshold,
            "an absurd threshold is clamped down");

        Properties.setValue("diveThreshold", 150);
        model.loadSettings();
        assertClose(model.dive_threshold, 1.5, "a sane threshold is taken as given");

        Properties.setValue("diveThreshold", 100);
        return true;
    }
}
