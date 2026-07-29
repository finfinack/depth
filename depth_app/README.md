# Depth (app)

An app showing the current water depth, inferred from the barometric pressure sensor.

A `watch-app` with a glance, not a `widget` — see [App, not widget](../README.md#app-not-widget) for why.

> ⚠️ **This is not a dive computer.** Do not rely on it for safety. See the [repository README](../README.md#this-is-not-a-dive-computer) for what that means, and [how it works](../README.md#how-it-works-and-drawbacks) for why the number can be wrong.

## Pages

Three pages, switched with swipe/press up and down like the built-in ones:

- **Summary** – both readings at once, shown first when the app is opened, inside the [gauge ring](#the-gauge-ring)
- **Depth** – the current water depth, full size, inside the ring
- **Max Depth** – the deepest reading since the app was opened, full size

Press Start on any page to re-zero, which drops the baseline and the maximum. That is what to use if the app was opened while already in the water.

The glance shows both values on one screen.

## The gauge ring

The Summary and Depth pages draw the [colour range](../README.md#colour-range) as a 270° ring around the reading, so the number has a scale behind it rather than standing on its own. It is the same gauge the [Depth Gauge](../depth_gauge/) data field puts on a full-screen layout, read exactly the same way:

| | |
| --- | --- |
| Current depth | A white **arrowhead** riding on the band |
| Session maximum | An orange **tick straight across** the band |

The ring ends one zone-width past the red boundary — 15 m on Snorkel, 40 m on Freedive, 80 m on Deep — rather than where red begins, so it still says something after it turns red. Past full scale the arrowhead stays at the deep end instead of wrapping round to the shallow one.

**Max Depth does not carry it.** Both other pages show the current depth, so on both the arrowhead points at a number that is on screen. On the Max Depth page the orange tick would only repeat what the page already says in full, and the arrowhead would sit at a depth that page is not showing.

**Round screens only.** The Instinct E 40 mm, Instinct E 45 mm and Instinct 3 Solar 45 mm are semi-octagons, where a ring on the screen's own radius runs off the flats — and they are the only 1-bit displays here, so the four zone colours would collapse into one anyway. Those watches keep the plain page.

## Reading it

The number is colour coded by depth — see the [colour range](../README.md#colour-range) for the bands, which depend on the profile setting. On the default Snorkel profile that is blue below 2 m, green to 5 m, yellow to 10 m and red beyond.

A small triangle next to the current depth shows which way it is going — **red pointing down** while descending, **blue pointing up** while ascending, and nothing at all while level. Red for deeper and blue for shallower matches the depth colour scale.

The trend needs the depth to be changing by more than about 0.15 m/s before it commits to a direction, and drops back to level below 0.08 m/s. Two thresholds rather than one, because a single sample of difference at 1 Hz is smaller than the sensor's own noise and an indicator driven straight off that would flicker constantly. In practice it commits within two or three seconds of a real descent.

There is no trend on the maximum — a maximum only ever moves one way.

[Settings](../README.md#settings) are in Garmin Connect under the app's settings.
