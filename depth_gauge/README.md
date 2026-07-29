# Depth Gauge (data field)

A data field showing where the current water depth sits in the colour range during an activity, the way a heart rate gauge shows a zone.

> ⚠️ **This is not a dive computer.** Do not rely on it for safety. See the [repository README](../README.md#this-is-not-a-dive-computer) for what that means, and [how it works](../README.md#how-it-works-and-drawbacks) for why the number can be wrong.

Laid out like the upper half of the watch's own heart rate zone gauge.

## What it draws

The colour profile's four bands as a scale, with the field's label, the current reading and the session maximum in the middle of it.

The zones come from the same numbers `depthColor()` colours by, so the gauge and the reading cannot disagree about what colour a depth is. The reading takes the colour of the zone it is in, exactly as the app's does.

The gauge runs to **one zone-width past the red boundary** — 15 m on Snorkel, 40 m on Freedive, 80 m on Deep — rather than ending where red begins. Ending it at the boundary would leave the last zone infinitely thin, and a gauge that pins the moment it turns red says nothing after that. Past full scale the marker stays at the deep end rather than wrapping round to the shallow one.

### Arc or bar

The scale is drawn as an arc or as a bar depending on the field, because a data field is handed anything from the whole screen to a band a few rows tall:

| Field | Shape |
| --- | --- |
| Full screen | A **270° arc** with the gap at the bottom, reading dead centre |
| Top half, bottom half | A **180° arc** over the apex or under the nadir |
| Everything else | A **bar** along the bottom, reading above it |

**A field given the whole screen gets the whole circle.** Picking a 1-field layout is the user saying they want this and nothing else, so the sweep opens out from 180° to 270° — from lower-left, over the top, to lower-right, with a gap at the bottom the way a speedometer or the watch's own zone gauges run. Shallow stays on the left exactly as it is on the half sweep, and the same four zones get half again as much angular resolution. The reading sits at the true centre of the lens rather than in the upper third, and the lower half of the screen stops being empty.

That layout is also the only one with rows to spare, so it is the only one that carries the **trend**: a red triangle pointing down while descending, blue pointing up while ascending, nothing while level — the same shapes and colours the [app](../depth_app/) uses, because an indicator should not have to be learnt twice. It is deliberately not the same shape as the arrowhead riding the band: that one points outwards along a radius and says *where* the reading is, this one says which way it is going.

The arc is *only ever* concentric with the display — never fitted into the field. That is what puts it on the bezel: an arc drawn on the lens's own centre is on the lens at every point, however large, so it needs no room inside a rectangle. A semicircle fitted into a rectangle inside the lens comes out at roughly **half** the radius, which is what this used to do.

**The sweep is trimmed, not the radius.** The arc's ends sit on the lens's horizontal diameter, and a field usually stops just short of it — a two-field top half is 260×**129** on a 260-row screen, one row shy of the centre at row 130. Rather than shrink the arc to fit that one row, the sweep is pulled in by the couple of degrees that keeps its ends on screen. On a fenix 7 the two-field arc spans **254 px of a 260 px field**; before this it was about 156.

An arc is used when the field spans the lens horizontally, holds the whole lens or one half of it, has an inside big enough for a legible number, and still has a sweep worth calling a scale (trimmed by no more than 15°). The 270° form needs the field to contain the lens vertically as well, which only a 1-field layout does. Everything else takes the bar. A semicircle is limited by the field's *height*, so in a four-field band 65 rows tall it would span a third of the width and leave the reading the scraps — backwards, since the reading is what is being read and the gauge is context around it. The bar uses the whole width and leaves the reading a real font size.

Checked against the layout rectangles the SDK ships for each device: on fenix 7, epix 2 and fenix 7S the 1-field, 2-field (both halves) and 3-Fields-C top layouts take the arc at full width; every other layout takes the bar, also at full width.

### Sizing

The band scales with what it sits on — 16% of the arc's radius, 26% of the field's height for the bar — and the arrowhead scales with the band, at 90% of its thickness. A marker that stays a fixed size looks like a speck on a full-screen gauge and swamps the band on a four-field one. On a fenix 7 that gives a 20 px ring with an 18×26 px arrowhead; on an epix 2, 32 px and 28×40 px.

### The two markers

| | |
| --- | --- |
| Current depth | A bright **arrowhead** riding on the band, pointing at its place on the scale |
| Session maximum | An orange **tick straight across** the band, with `MAX` and the depth under the reading |

Two different shapes on purpose. A second arrowhead would read as a second current reading, and on the arc a short segment in another colour would just read as one more zone — so the maximum crosses the band rather than following it, and says what it is in words whenever the field has a row to spare.

The label and the maximum are both dropped when what is left of the field cannot hold them; the reading has first call on the space, and whether the other two fit is measured rather than guessed at, so a long translation drops its own line instead of running off the side.

## Round screens

Almost every device this ships to is round, and a data field is handed a rectangle regardless — see [the repository README](../README.md#round-screens) for the three semi-octagon Instincts, where the lens geometry switches off and the gauge always takes the bar.

The gauge is the one thing here that does not want a rectangle, which is why the barrel exposes the lens circle as well as its rows and columns — see [Arc or bar](#arc-or-bar) above for what it does with it. A field holding the *bottom* half of the lens gets the same arc mirrored, sweeping under the nadir instead of over the apex, so the two halves of a split screen look like two halves of one gauge.

Anything the arc cannot serve — a corner field, a screen that is not round — takes the bar, which uses the rows and columns like everything else. The geometry is [`DepthFieldLayout`](../DepthCore/README.md#drawing-on-a-round-screen) in the barrel, shared with Depth Chart.

### A known limit

`getObscurityFlags()` says which of a field's sides the lens cuts, and the field's size is known, but Connect IQ exposes **no way to ask where the field is**. The position is inferred from the two: a field touching the left edge starts at 0, one touching the right ends at the screen edge, one touching both is full width.

A field touching *neither* edge on an axis cannot be placed this way, and the code assumes it is centred. Checked against the SDK's own layout rectangles that assumption is exact for the 1-, 2- and 3-field layouts, but wrong for the stacked middle bands of the denser ones — the system stacks those rather than centring them, by up to 2.8× the field's height. Those fields can therefore have their outermost pixels drawn under the bezel.

It does not affect the arc: every layout that takes the arc touches the top or the bottom, so its position is exact. It affects the bar and the chart on middle bands of 4-field-and-denser layouts only.

## What it records

**Nothing.** The per-record depth series and the raw pressure belong to the [Depth field](../depth_field/README.md#what-it-records) and the session maximum to [Max Depth](../max_depth_field/); writing them here as well would duplicate the whole graph in Garmin Connect for anyone running two of these at once.

Pair this with the Depth field if the activity should carry the data as well as show it.

Nothing is kept between samples either — the gauge shows where the reading is now, and the shared model already holds the maximum.

[Settings](../README.md#settings) are in Garmin Connect under the app's settings.
