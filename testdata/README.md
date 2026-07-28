# Test data

Sensor input for the simulator. The depth apps derive everything they show
from barometric pressure, and the simulator reports no pressure at all until
it is given some — `Activity.Info.rawAmbientPressure` and `ambientPressure`
are both `null`, so every field shows `n/a` and the graph field draws nothing
but its surface line. That is the simulator being empty, not the apps being
broken.

## dive_profile.fit

Two breath-hold dives with a surface interval between them, one sample a
second for 150 s, as `record.absolute_pressure` in pascal:

| Time      | Depth                    |
| --------- | ------------------------ |
| 0–15 s    | surface                  |
| 15–45 s   | descending to 12 m       |
| 45–75 s   | holding 12 m, with swell |
| 75–100 s  | ascending                |
| 100–115 s | surface interval         |
| 115–130 s | descending to 6 m        |
| 130–150 s | ascending                |

The pressures are fresh water at sea level, `101325 Pa + depth * 9806.65 Pa`,
which matches the default of the `waterType` setting. With the setting on salt
the apps read about 2% shallow against this file — that is the convention
difference described in the main README, not an error.

Two dives rather than one on purpose: the second is what shows that the
session maximum holds after the first dive ends, and it gives the graph field's
chart something with shape to draw.

### Loading it

In the simulator, `Simulation > Activity Data`, and pick the file. Data
simulation and file playback are mutually exclusive — the same menu stops
whichever is running.

The generated data in the same menu is the other option, and is worth knowing
about: it produces a plausible ambient pressure (around 94 kPa, so an altitude
of roughly 600 m) that drifts by a few pascal a second. That is enough to prove
a field is reading the sensor at all, but it never goes below the surface, so
the colour bands, the maximum and the chart all stay where they start.

### Regenerating it

```sh
cd testdata
python3 make_dive_fit.py
```

`make_dive_fit.py` writes the FIT by hand — one message type and a CRC, rather
than a dependency on the Garmin FIT SDK. Edit `profile()` to change the dive
and re-run. Nothing in the build or the tests reads either file; they are here
to be loaded by hand.

### What has and has not been checked

The file is structurally valid — header CRC, file CRC and message sizes all
verify, and it decodes back to 150 `record` messages carrying the pressures
above.

What has **not** been confirmed is that the simulator maps
`record.absolute_pressure` onto `Activity.Info.ambientPressure` when it plays
a FIT back. Loading a file is a menu action, and the `fit_parse` command in the
SDK's `shell` did not drive the simulator from the command line — not with this
file and not with Garmin's own `samples/PitchCounter/pitch_counter_8_pitches.FIT`
either — so it could not be checked without the GUI. If the apps still show
`n/a` with this file playing, that mapping is the thing to suspect first, and
`record.depth` (field 92) is the field to try instead.

What *is* confirmed is the other half: with the simulator's generated data
switched on, a data field's `compute()` receives real values in
`rawAmbientPressure` and `ambientPressure`, and receives `null` in both the
moment it is switched off.
