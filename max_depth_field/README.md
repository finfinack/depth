# Max Depth (data field)

A data field showing the deepest water depth reached since the activity started, inferred from the barometric pressure sensor.

> ⚠️ **This is not a dive computer.** Do not rely on it for safety. See the [repository README](../README.md#this-is-not-a-dive-computer) for what that means, and [how it works](../README.md#how-it-works-and-drawbacks) for why the number can be wrong.

The unit is shown in the field label (`Max Depth (m)` / `Max Depth (ft)`), because a simple data field has no room for a suffix on the value itself.

A new maximum has to be supported by two consecutive readings before it counts, and anything descending faster than 3 m/s is discarded as a sensor glitch. Between them these keep a single noisy sample from latching into the maximum permanently, where it would stay for the rest of the activity.

## What it records

The field writes four developer fields into the activity's FIT file, all of them summaries of the whole activity:

| Field | Scope | Unit | Meaning |
| --- | --- | --- | --- |
| `max_depth` | session | cm | The deepest reading of the whole activity |
| `max_depth_raw` | session | cm | The same, with no spike rejection at all |
| `dive_count` | session | — | How many times you went below the [dive threshold](../depth_app/README.md#what-counts-as-a-dive) |
| `total_bottom_time` | session | s | How long was spent below it, added up |

Centimetres whatever the display unit is set to, and clamped to 655.34 m — see the [Depth field README](../depth_field/README.md#what-it-records) for why, and for what the raw maximum is for.

`max_depth_raw` earns its place here more than it does there. The Depth field records the whole depth series, so a raw maximum could be recovered from it afterwards; this field records no series at all, so without it there would be nothing to check the rejected peak against.

This field deliberately records no per-record series. The [Depth field](../depth_field/) already contributes one, along with the raw pressure, and writing it from both would duplicate the entire graph for anyone running the two together.

[Settings](../README.md#settings) are in Garmin Connect under the app's settings.
