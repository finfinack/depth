# Depth Gauge (data field)

A data field showing where the current water depth sits in the colour range during an activity, the way a heart rate gauge shows a zone.

> ⚠️ **This is not a dive computer.** Do not rely on it for safety. See the [repository README](../README.md#this-is-not-a-dive-computer) for what that means, and [how it works](../README.md#how-it-works-and-drawbacks) for why the number can be wrong.

Laid out like the upper half of the watch's own heart rate zone gauge.

## What it draws

The colour profile's four bands as a scale, with the field's label, the current reading and the session maximum in the middle of it.

The zones come from the same numbers `depthColor()` colours by, so the gauge and the reading cannot disagree about what colour a depth is. The reading takes the colour of the zone it is in, exactly as the widget's does.

The gauge runs to **one zone-width past the red boundary** — 15 m on Snorkel, 40 m on Freedive, 80 m on Deep — rather than ending where red begins. Ending it at the boundary would leave the last zone infinitely thin, and a gauge that pins the moment it turns red says nothing after that. Past full scale the marker stays at the deep end rather than wrapping round to the shallow one.

### Arc or bar

The scale is drawn as an arc or as a bar depending on the field, because a data field is handed anything from the whole screen to a band a few rows tall:

| Field | Shape |
| --- | --- |
| Full-screen, top half | An arc **concentric with the display**, running along the bezel |
| Bottom half, and other roughly square fields | A semicircle **fitted into the field** |
| Three- and four-field layouts, quarter fields | A **bar** along the bottom, reading above it |

A semicircle is limited by the field's *height*: it is twice as wide as it is tall, so in a four-field band 65 rows tall it spans about a third of the width and leaves the reading the scraps. That is backwards — the reading is what is being read and the gauge is context around it — so those fields get a bar, which uses the whole width and leaves the reading a real font size.

An arc is only chosen when it can manage **at least 75% of the field's width** and a radius large enough to hold a legible number inside it. Everything else takes the bar, and a field too small even for a bar drops it and shows the reading alone rather than sharing the space with something illegible.

Measured across the layouts on a 260 px screen, the scale spans the full usable width in every case, and the reading lands on the largest font in all but the two narrowest four-field bands and the quarter field.

### The two markers

| | |
| --- | --- |
| Current depth | A bright **arrowhead** riding on the band, pointing at its place on the scale |
| Session maximum | An orange **tick straight across** the band, with `MAX` and the depth under the reading |

Two different shapes on purpose. A second arrowhead would read as a second current reading, and on the arc a short segment in another colour would just read as one more zone — so the maximum crosses the band rather than following it, and says what it is in words whenever the field has a row to spare.

The label and the maximum are both dropped when what is left of the field cannot hold them; the reading has first call on the space, and whether the other two fit is measured rather than guessed at, so a long translation drops its own line instead of running off the side.

## Round screens

Every device this ships to is round, and a data field is handed a rectangle regardless — see [the repository README](../README.md#round-screens).

The gauge is the one thing here that does not want a rectangle. An arc drawn **concentric with the display** is on the lens at every point, however large it is, so wherever the field can hold the upper half of that circle — full-screen, or the top half of the screen — the arc is drawn on the display's own centre and runs right along the bezel, like the watch's own zone gauges. Fitting it into a rectangle inside the lens instead would shrink it to about half the screen it could have used.

Anything else — a bottom field, a corner field, a screen that is not round — falls back to a semicircle fitted into the field, or to the bar when the field is the wrong shape for one, as [above](#arc-or-bar). The geometry is [`DepthFieldLayout`](../DepthCore/README.md#drawing-on-a-round-screen) in the barrel, shared with Depth Chart.

## What it records

**Nothing.** The per-record depth series and the raw pressure belong to the [Depth field](../depth_field/README.md#what-it-records) and the session maximum to [Max Depth](../max_depth_field/); writing them here as well would duplicate the whole graph in Garmin Connect for anyone running two of these at once.

Pair this with the Depth field if the activity should carry the data as well as show it.

Nothing is kept between samples either — the gauge shows where the reading is now, and the shared model already holds the maximum.

[Settings](../README.md#settings) are in Garmin Connect under the app's settings.
