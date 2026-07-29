import Toybox.Graphics;
import Toybox.Lang;

module DepthCore {

    //! Values of the colorProfile setting, and so of DepthModel.color_profile.
    (:glance) const PROFILE_SNORKEL = 0;
    (:glance) const PROFILE_FREEDIVE = 1;
    (:glance) const PROFILE_DEEP = 2;

    // The depths each profile changes colour at, in meters, shallow to deep.
    //
    // Module constants rather than literals inside depthColor(), because the
    // graph field's gauge has to draw the same boundaries it colours by and two
    // copies of these numbers would drift apart. They are allocated once at
    // load and shared, so profileBands() below hands out a reference rather
    // than building an array — depthColor() runs once per pixel column of the
    // graph, and an allocation per call there would be real churn.
    (:glance) const SNORKEL_BANDS = [2.0, 5.0, 10.0] as Array<Float>;
    (:glance) const FREEDIVE_BANDS = [10.0, 20.0, 30.0] as Array<Float>;
    (:glance) const DEEP_BANDS = [20.0, 40.0, 60.0] as Array<Float>;

    //! The three depths, in meters, where the given profile changes colour:
    //! blue below the first, then green, then yellow, and red at or past the
    //! third. An unknown profile gets the snorkelling bands.
    (:glance)
    function profileBands(profile as Number) as Array<Float> {
        if (profile == PROFILE_FREEDIVE) {
            return FREEDIVE_BANDS;
        }
        if (profile == PROFILE_DEEP) {
            return DEEP_BANDS;
        }
        return SNORKEL_BANDS;
    }

    //! Colour scale for a depth read-out, shared by the app and the glance.
    //!
    //! Shallow water reads blue and the colour warms up as it gets deeper, so
    //! the reading can be judged without actually reading the number. That only
    //! works if the bands cover the range being swum: at the freediving scale a
    //! snorkeller never leaves the first band and the colour says nothing at
    //! all, which is what the profile is for.
    //!
    //! The thresholds are in meters regardless of the display unit, because they
    //! describe the physical depth. An unknown profile gets the snorkelling
    //! bands, which is also what an app that never declares the setting gets.
    (:glance)
    function depthColor(meters as Float?, profile as Number) as Graphics.ColorType {
        if (meters == null) {
            return Graphics.COLOR_LT_GRAY;
        }

        var bands = profileBands(profile);
        if (meters < bands[0]) {
            return Graphics.COLOR_BLUE;
        }
        if (meters < bands[1]) {
            return Graphics.COLOR_GREEN;
        }
        if (meters < bands[2]) {
            return Graphics.COLOR_YELLOW;
        }
        return Graphics.COLOR_RED;
    }

    //! The colour a read-out is drawn in: its depth band normally, red when the
    //! reading is a lower bound because the sensor is pinned.
    //!
    //! Red rather than a fifth colour of its own, because red is already the
    //! "you are deep" end of every profile and so reads as a warning without
    //! anything to learn — and the ">=" in front of the number says which kind
    //! of warning it is. It does not collide with the band it replaces: a
    //! ceiling anywhere near the reported 6-7 m is yellow on the snorkelling
    //! scale and blue on the other two, so red is never what would have been
    //! shown anyway.
    //!
    //! The bands themselves keep depthColor(). Recolouring the chart's whole
    //! body of water red would destroy the scale it is drawn to, and the scale
    //! is still true down to wherever the sensor stopped.
    (:glance)
    function readingColor(meters as Float?, profile as Number,
                          limited as Boolean) as Graphics.ColorType {
        if (limited && meters != null) {
            return Graphics.COLOR_RED;
        }
        return depthColor(meters, profile);
    }
}
