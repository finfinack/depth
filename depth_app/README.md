# Depth (app)

An app showing the current water depth, inferred from the barometric pressure sensor.

A `watch-app` with a glance. [`depth_widget`](../depth_widget/) is this same program built as a `widget` and is what currently ships — see [Widget and app](../README.md#widget-and-app). Everything below is true of both; install one of the two.

> ⚠️ **This is not a dive computer.** Do not rely on it for safety. See the [repository README](../README.md#this-is-not-a-dive-computer) for what that means, and [how it works](../README.md#how-it-works-and-drawbacks) for why the number can be wrong.

## Pages

Two pages, three once you have been in the water, switched with swipe/press up and down like the built-in ones:

- **Summary** – the current depth, with the session maximum under it and the [gauge ring](#the-gauge-ring) around both
- **Session** – how this outing is going: dives so far and time spent under
- **Last Session** – what the previous outing came to, if there was one. See [below](#last-session)

The depth and the maximum are not given equal billing on the Summary. The depth gets the heading and the full-size number because it is what the app is opened to read, and it is what the ring refers to; the maximum sits under it in a smaller hand as context.

There used to be separate full-screen Depth and Max Depth pages. Both were dropped: each showed a number the Summary already shows, and the Summary now shows it against the ring, which is worth more than a bigger font was.

Press Start on any page to re-zero, which drops the baseline and the maximum. That is what to use if the app was opened while already in the water.

The glance shows both values on one screen.

## Last Session

Max depth, how many dives, and how long was spent under — from the last time the app was open and you actually went in.

**"Session" means one run of this app, not one recorded activity.** The app cannot see what [Depth](../depth_field/) or [Max Depth](../max_depth_field/) recorded during an activity: they are separate Connect IQ apps with their own storage, and nothing is shared between app IDs. If you snorkel with a data field on a recorded activity instead, the same three numbers are [in the FIT file](../depth_field/README.md#what-it-records) and Garmin Connect shows them afterwards.

**Only a run that recorded a dive is stored**, which is what stops the page erasing itself. Opening the app to check something — or to read this very page — counts no dives and writes nothing, so the real outing survives. Scrolling past the glance cannot overwrite it either: glance mode never builds the app's model, and the save is guarded on it.

The page only exists once there is a session to put on it. Before your first stored outing there are two pages, not three.

### What counts as a dive

Going below the **Dive threshold** setting, default 1.0 m. The dive ends when you come back up past *half* that depth, not at the threshold itself — with a single line, a diver hovering right on it would score a new dive every time they grazed it, the same chatter the [trend](#reading-it) uses two thresholds to avoid. Half is far enough that surface chop cannot bridge it, close enough that a real ascent ends the dive promptly.

Bottom time adds up the interval each reading stands for, rather than timing from the start of a dive to its end. That way a gap in the readings is simply not counted: if the sensor drops out for two minutes while you are under, those two minutes are not claimed as time on the bottom.

Both numbers reset on a [re-zero](#pages), alongside the maximum.

## The gauge ring

The Summary page draws the [colour range](../README.md#colour-range) as a 270° ring around the reading, so the number has a scale behind it rather than standing on its own. It is the same gauge the [Depth Gauge](../depth_gauge/) data field puts on a full-screen layout, read exactly the same way:

| | |
| --- | --- |
| Current depth | A white **arrowhead** riding on the band |
| Session maximum | An orange **tick straight across** the band |

The ring ends one zone-width past the red boundary — 15 m on Snorkel, 40 m on Freedive, 80 m on Deep — rather than where red begins, so it still says something after it turns red. Past full scale the arrowhead stays at the deep end instead of wrapping round to the shallow one.

**Only the Summary carries it**, because it is the only page showing the current depth — and the current depth is what the arrowhead points at. The two session pages are about totals, where nothing on the ring would refer to what is being read.

**Round screens only.** The Instinct E 40 mm, Instinct E 45 mm and Instinct 3 Solar 45 mm are semi-octagons, where a ring on the screen's own radius runs off the flats — and they are the only 1-bit displays here, so the four zone colours would collapse into one anyway. Those watches keep the plain page.

## The depth buzz

The watch buzzes on the way down as you pass each boundary of the [colour range](../README.md#colour-range) — **once** at the first, **twice** at the second, **three times** at the third. On the default Snorkel range that is 2 m, 5 m and 10 m; on Freedive it is 10, 20 and 30.

> ⚠️ **It is not a dive alarm.** It says which band you have reached and nothing else. See [what that means](../README.md#this-is-not-a-dive-computer).

**The same boundaries as everything else**, rather than a set of its own. The number changes colour, the [gauge ring](#the-gauge-ring)'s arrowhead moves into the next zone and the wrist buzzes at one depth, so a diver who has learnt the colours has already learnt the buzzes — and there is one list of depths in the settings, not two that have to be kept in step.

Four things about how it fires:

- **Going down only.** A boundary crossed on the way up is the same depth arrived at from the other side and says nothing new; buzzing both ways would double every buzz on an ordinary dive.
- **The pulse count is the boundary you reached, not how many you crossed.** A descent quick enough to pass two between readings buzzes twice, because two is the band you are now in.
- **Once per crossing.** A boundary is only armed again once you come back up 0.3 m clear of it, so hovering right on 2 m with chop under you is one buzz, not one per second. Same reasoning as the [dive count](#what-counts-as-a-dive)'s two thresholds.
- **It follows the watch.** With vibration switched off in the watch's own settings, nothing buzzes here either.

Changing the colour range mid-outing does not buzz its way through the new boundaries: the depths moved, you did not, so the new range takes effect from where you already are.

**Only the app buzzes, not the data fields.** A data field could — `Toybox.Attention` is available to them — but the four of them are designed to be run together, and they cannot see each other: separate Connect IQ apps, separate app IDs, no shared anything. Somebody snorkelling with [Depth](../depth_field/) on one screen and [Depth Gauge](../depth_gauge/) on another would be buzzed twice at every boundary, three times with a third field, and nothing in any of them could tell. That is the same reason [only one of them records the depth series](../README.md#the-two-drawn-fields), and it counts for more on a buzz than on a chart: a duplicated graph is untidy, a duplicated alert is misread as a different alert.

Turn it off with **Depth buzz** in [the settings](../README.md#settings).

## Reading it

The number is colour coded by depth — see the [colour range](../README.md#colour-range) for the bands, which depend on the profile setting. On the default Snorkel profile that is blue below 2 m, green to 5 m, yellow to 10 m and red beyond.

A small triangle next to the current depth shows which way it is going — **red pointing down** while descending, **blue pointing up** while ascending, and nothing at all while level. Red for deeper and blue for shallower matches the depth colour scale.

The trend needs the depth to be changing by more than about 0.15 m/s before it commits to a direction, and drops back to level below 0.08 m/s. Two thresholds rather than one, because a single sample of difference at 1 Hz is smaller than the sensor's own noise and an indicator driven straight off that would flicker constantly. In practice it commits within two or three seconds of a real descent.

There is no trend on the maximum — a maximum only ever moves one way.

[Settings](../README.md#settings) are in Garmin Connect under the app's settings.
