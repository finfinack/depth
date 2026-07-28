# Max Depth (data field)

A data field showing the deepest water depth reached since the activity started, inferred from the barometric pressure sensor.

> ⚠️ **This is not a dive computer.** Do not rely on it for safety. See the [repository README](../README.md#this-is-not-a-dive-computer) for what that means, and [how it works](../README.md#how-it-works-and-drawbacks) for why the number can be wrong.

The unit is shown in the field label (`Max Depth (m)` / `Max Depth (ft)`), because a simple data field has no room for a suffix on the value itself.

A new maximum has to be supported by two consecutive readings before it counts, and anything descending faster than 3 m/s is discarded as a sensor glitch. Between them these keep a single noisy sample from latching into the maximum permanently, where it would stay for the rest of the activity.

## What it records

The field writes one developer field into the activity's FIT file:

| Field | Scope | Unit | Meaning |
| --- | --- | --- | --- |
| `max_depth` | session | cm | The deepest reading of the whole activity |

Centimetres whatever the display unit is set to, and clamped to 655.35 m — see the [Depth field README](../depth_field/README.md#what-it-records) for why.

This field deliberately records no per-record series. The [Depth field](../depth_field/) already contributes one, along with the raw pressure, and writing it from both would duplicate the entire graph for anyone running the two together.

[Settings](../README.md#settings) are in Garmin Connect under the app's settings.
