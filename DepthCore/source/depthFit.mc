import Toybox.Lang;

//! Helpers for contributing depth to the FIT file. Deliberately not annotated
//! (:glance) — the glance shows a reading, it never records one, and glance
//! scope is the tightest memory budget in the project.
module DepthCore {

    //! The largest value a FIT UINT16 field can hold.
    const fit_uint16_max = 65535;

    //! Ceiling for a recorded pressure, in pascal. A UINT32 goes far higher,
    //! but a Monkey C Number is signed 32-bit and cannot even hold the UINT32
    //! maximum, so the clamp has to sit somewhere below it. 2 MPa is roughly
    //! 190 m of water — orders of magnitude past anything a watch barometer can
    //! report, which is the point: this bounds garbage, not real readings.
    const fit_pressure_max = 2000000;

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

    //! Convert an ambient pressure in pascal to the whole pascal written to the
    //! FIT file, clamped the same way and for the same reasons as above.
    //!
    //! This is the sensor reading before anything is done to it, which is what
    //! makes it worth recording: the depth series depends on a surface baseline
    //! the app had to guess at, and a guess cannot be checked from its own
    //! output. Pressure can, and it shows sensor saturation directly.
    function pressurePascals(pascal as Float?) as Number {
        if (pascal == null) {
            return 0;
        }

        if (pascal > 0.0) {
            if (pascal >= fit_pressure_max) {
                return fit_pressure_max;
            }
            return (pascal + 0.5).toNumber();
        }
        return 0;
    }
}
