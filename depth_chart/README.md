# Depth Chart (data field)

A data field plotting the last two minutes of water depth against time during an activity, inferred from the barometric pressure sensor.

> ⚠️ **This is not a dive computer.** Do not rely on it for safety. See the [repository README](../README.md#this-is-not-a-dive-computer) for what that means, and [how it works](../README.md#how-it-works-and-drawbacks) for why the number can be wrong.

Laid out like the watch's own barometer field.

## What it draws

The heading is the field's label and the current reading, coloured by the [colour range](../README.md#colour-range) — the same colour the widget gives that depth.

Below it, depth deepens **downwards** from a surface line at the top. Time runs left to right with the newest sample at the right edge, and the axis stays two minutes wide however much history there is, so a field that has just started fills in from the right rather than stretching ten seconds across the whole chart. Gaps where there was no reading are left as gaps.

### The fill

The chart is not a line but a **solid body of water** hanging from the surface line down to the trace.

That is the barometer field's own fill, and it means something here rather than being decoration: depth is measured down from the surface, so the block between the surface line and the trace *is* the reading. It makes the chart read as water at a glance instead of as a graph that has to be traced with the eye.

The fill is banded blue, green, yellow and red as it deepens, at the profile's own boundaries — the same numbers `depthColor()` uses. The bands are horizontal and at fixed depths, so they double as a scale: whichever colour the waterline is sitting in is the colour the reading above it is showing. A thin bright edge marks where the water stops, so the trace still reads as a line over time as well.

### The maximum, at the bottom

**The bottom edge of the chart is the session maximum.** The chart scales to the deepest the session has been rather than to fixed steps, so the maximum is the floor of the picture — an orange line along the bottom carrying `MAX` and the depth.

The point is to leave exactly one reference on the chart. A line floating somewhere in the middle reads as a threshold or an average as readily as a maximum, however it is drawn, and it also needed a second number in the corner to say what the bottom edge was worth. Putting the maximum *at* the bottom collapses both into one.

Two consequences:

- The chart rescales as the maximum grows, rather than holding still. That is the trade for the above.
- A shallow session is floored at **0.5 m**, which is already inside the band the model treats as "at the surface". Without a floor a two-centimetre maximum would stretch the sensor's own noise across the whole field. When the floor is what is in force, the orange line is drawn where the maximum really is rather than at the bottom, and still labelled — the chart never claims a maximum it does not have.

## Round screens

Every device this ships to is round, and a data field is handed a rectangle regardless — see [the repository README](../README.md#round-screens). The chart measures where it sits before drawing, places its heading below the rows the lens has pinched away, and fills the water one column at a time out to the curve rather than squaring itself off inside it — which on a corner field is most of the usable area. The geometry is [`DepthFieldLayout`](../DepthCore/README.md#drawing-on-a-round-screen) in the barrel, shared with Depth Gauge.

## What it records

**Nothing.** The per-record depth series and the raw pressure belong to the [Depth field](../depth_field/README.md#what-it-records) and the session maximum to [Max Depth](../max_depth_field/); writing them here as well would duplicate the whole graph in Garmin Connect for anyone running two of these at once.

Pair this with the Depth field if the activity should carry the data as well as show it.

[Settings](../README.md#settings) are in Garmin Connect under the app's settings.
