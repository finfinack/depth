# Depth (data field)

A data field showing the current water depth during an activity, inferred from the barometric pressure sensor.

> ⚠️ **This is not a dive computer.** Do not rely on it for safety. See the [repository README](../README.md#this-is-not-a-dive-computer) for what that means, and [how it works](../README.md#how-it-works-and-drawbacks) for why the number can be wrong.

The unit is shown in the field label (`Depth (m)` / `Depth (ft)`), because a simple data field has no room for a suffix on the value itself.

## What it records

The field writes three developer fields into the activity's FIT file, so the dive is kept rather than just displayed:

| Field | Scope | Unit | Meaning |
| --- | --- | --- | --- |
| `depth` | every record | cm | The depth at that moment, which Garmin Connect draws as a graph |
| `pressure` | every record | Pa | The raw sensor reading the depth was derived from |
| `max_depth` | session | cm | The deepest reading of the whole activity |

Depth is always in **centimetres**, whatever the display unit is set to. The unit setting can be changed part way through an activity, and a recorded field whose meaning changed halfway would be worse than useless. Centimetres are also exactly the resolution the field displays, so nothing is lost. Values are clamped to 655.35 m: the model puts no ceiling on depth, and without the clamp a wild reading would wrap around into a small number that looked entirely plausible.

**`pressure` is the one to look at when the depth seems wrong.** Depth is only as good as the [guessed surface baseline](../README.md#how-it-works-and-drawbacks), and a guess cannot be checked against its own output. The pressure is the unprocessed input, so it lets you recompute depth afterwards against any surface pressure and water density you like — and it shows sensor saturation directly, as a trace that climbs and then flattens into a hard ceiling no matter how much deeper you go.

Note that the displayed depth is *not* smoothed — it is the raw pressure against the tracked baseline. The only place any smoothing exists is the widget's trend indicator, which needs it because a one-sample difference is smaller than the sensor's noise.

If you also run the **Max Depth** field in the same activity, it contributes only its own session maximum — the per-record series is not written twice.

[Settings](../README.md#settings) are in Garmin Connect under the app's settings.
