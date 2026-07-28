import Toybox.Graphics;
import Toybox.Lang;

module DepthCore {

    //! Values of the colorProfile setting, and so of DepthModel.color_profile.
    //! The bands each one uses are in depthColor() below.
    (:glance) const PROFILE_SNORKEL = 0;
    (:glance) const PROFILE_FREEDIVE = 1;
    (:glance) const PROFILE_DEEP = 2;

    //! Colour scale for a depth read-out, shared by the widget and the glance.
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

        // Band boundaries in meters, shallow to deep. Written out per profile
        // rather than held in an array: three floats on the stack cost less
        // than three arrays in a module, and glance scope is the tightest
        // memory budget in the project.
        var green = 2.0;
        var yellow = 5.0;
        var red = 10.0;
        if (profile == PROFILE_FREEDIVE) {
            green = 10.0;
            yellow = 20.0;
            red = 30.0;
        } else if (profile == PROFILE_DEEP) {
            green = 20.0;
            yellow = 40.0;
            red = 60.0;
        }

        if (meters < green) {
            return Graphics.COLOR_BLUE;
        }
        if (meters < yellow) {
            return Graphics.COLOR_GREEN;
        }
        if (meters < red) {
            return Graphics.COLOR_YELLOW;
        }
        return Graphics.COLOR_RED;
    }
}
