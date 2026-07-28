# Depth (widget)

A widget showing the current water depth, inferred from the barometric pressure sensor.

> ⚠️ **This is not a dive computer.** Do not rely on it for safety. See the [repository README](../README.md#this-is-not-a-dive-computer) for what that means, and [how it works](../README.md#how-it-works-and-drawbacks) for why the number can be wrong.

## Pages

Three pages, switched with swipe/press up and down like the built-in widgets:

- **Summary** – both readings at once, shown first when the widget is opened
- **Depth** – the current water depth, full size
- **Max Depth** – the deepest reading since the widget was opened, full size

Press Start on any page to re-zero, which drops the baseline and the maximum. That is what to use if the widget was opened while already in the water.

The glance shows both values on one screen.

## Reading it

The number is colour coded by depth: blue below 10 m, green to 20 m, yellow to 30 m and red beyond that.

A small triangle next to the current depth shows which way it is going — **red pointing down** while descending, **blue pointing up** while ascending, and nothing at all while level. Red for deeper and blue for shallower matches the depth colour scale.

The trend needs the depth to be changing by more than about 0.15 m/s before it commits to a direction, and drops back to level below 0.08 m/s. Two thresholds rather than one, because a single sample of difference at 1 Hz is smaller than the sensor's own noise and an indicator driven straight off that would flicker constantly. In practice it commits within two or three seconds of a real descent.

There is no trend on the maximum — a maximum only ever moves one way.

[Settings](../README.md#settings) are in Garmin Connect under the app's settings.
