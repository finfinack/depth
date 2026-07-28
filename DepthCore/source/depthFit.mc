import Toybox.Lang;

//! Helpers for contributing depth to the FIT file. Deliberately not annotated
//! (:glance) — the glance shows a reading, it never records one, and glance
//! scope is the tightest memory budget in the project.
module DepthCore {

    //! The largest value a FIT UINT16 field can hold.
    const fit_uint16_max = 65535;

    //! Convert a depth in meters to the centimeters written to the FIT file.
    //!
    //! Centimeters in a UINT16 cover 0–655 m at exactly the resolution the
    //! display shows, and cost half of what a float would in every record.
    //!
    //! The model puts no ceiling on depth, so this clamps instead of letting a
    //! wild pressure reading wrap around into a plausible-looking small number.
    //! Comparing in the float domain matters: a large enough value would
    //! overflow a Number before there was anything left to clamp. Zero,
    //! negative and NaN all fall through to 0.
    function depthCentimeters(meters as Float?) as Number {
        if (meters == null) {
            return 0;
        }

        var centimeters = meters * 100.0;
        if (centimeters > 0.0) {
            if (centimeters >= fit_uint16_max) {
                return fit_uint16_max;
            }
            return (centimeters + 0.5).toNumber();
        }
        return 0;
    }
}
