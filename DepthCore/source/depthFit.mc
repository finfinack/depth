import Toybox.Lang;

//! Helpers for contributing depth to the FIT file. Deliberately not annotated
//! (:glance) — the glance shows a reading, it never records one, and glance
//! scope is the tightest memory budget in the project.
module DepthCore {

    //! The FIT profile's "no reading" marker for a UINT16 field. A parser that
    //! sees 0xFFFF drops the sample rather than plotting it.
    const fit_uint16_invalid = 65535;

    //! ...so the deepest value that can actually be *recorded* is one below it.
    //! Clamping to the marker itself would file garbage as absent rather than
    //! as pinned at the ceiling, which is the opposite of what a clamp is for.
    //!
    //! 655.34 m either way — orders of magnitude past anything a watch
    //! barometer can report, which is the point: this bounds garbage, not
    //! readings.
    const fit_depth_max = fit_uint16_invalid - 1;

    //! Largest value any UINT16 field here may carry — the same bound as
    //! fit_depth_max, which keeps its own name because the reasoning for it is
    //! about depths rather than about counts.
    const fit_uint16_max = fit_uint16_invalid - 1;

    //! Ceiling for a recorded pressure, in pascal. A UINT32 goes far higher,
    //! but a Monkey C Number is signed 32-bit and cannot even hold the UINT32
    //! maximum, so the clamp has to sit somewhere below it. 2 MPa is roughly
    //! 190 m of water — orders of magnitude past anything a watch barometer can
    //! report, which is the point: this bounds garbage, not real readings.
    //!
    //! No collision with the UINT32 invalid marker to worry about here, the way
    //! there is above: 0xFFFFFFFF is three orders of magnitude further out than
    //! this ceiling, and unreachable from a signed Number in any case.
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
            if (centimeters >= fit_depth_max) {
                return fit_depth_max;
            }
            return (centimeters + 0.5).toNumber();
        }
        return 0;
    }

    //! Clamp a count into the UINT16 a FIT count field carries.
    //!
    //! 65534 dives is not reachable in a session — at the very fastest a dive
    //! takes seconds, so this is bounding a runaway counter rather than a real
    //! total. It exists because writing the invalid marker would file the count
    //! as "not recorded", which is a worse answer than "more than we can say".
    function fitCount(count as Number) as Number {
        if (count <= 0) {
            return 0;
        }
        return (count > fit_uint16_max) ? fit_uint16_max : count;
    }

    //! Milliseconds to the whole seconds a FIT duration field carries.
    //!
    //! Truncates rather than rounds: bottom time is a sum of intervals that
    //! were each measured to the sample, so the last fraction of a second was
    //! never really known. Under-claiming it is the honest direction.
    function fitSeconds(milliseconds as Number) as Number {
        if (milliseconds <= 0) {
            return 0;
        }
        return milliseconds / 1000;
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
