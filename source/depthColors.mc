import Toybox.Graphics;
import Toybox.Lang;

//! Colour scale for a depth read-out, shared by the widget and the glance.
//!
//! Shallow water reads blue and the colour warms up as it gets deeper, so the
//! reading can be judged without actually reading the number. The thresholds
//! are in meters regardless of the display unit, because they describe the
//! physical depth.
(:glance)
function depthColor(meters as Float?) as Graphics.ColorType {
    if (meters == null) {
        return Graphics.COLOR_LT_GRAY;
    }
    if (meters < 10.0) {
        return Graphics.COLOR_BLUE;
    }
    if (meters < 20.0) {
        return Graphics.COLOR_GREEN;
    }
    if (meters < 30.0) {
        return Graphics.COLOR_YELLOW;
    }
    return Graphics.COLOR_RED;
}
