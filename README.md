# Depth

Barometric depth for Garmin watches (Fenix, Epix, Tactix) — a widget, four data fields, and the model they share.

Find them on the [Garmin ConnectIQ store](https://apps.garmin.com/developer/1e45545b-eec0-40b0-886d-61739dd6f510/apps) for free to install them.

Previously three separate repositories. They are one now because all three carried an identical copy of the depth model, and keeping three copies in step by hand was the main source of drift.

| Project | Type | What it is |
| --- | --- | --- |
| [DepthCore](DepthCore/) | Monkey Barrel | The depth model, colour scale, FIT helpers and the data field layout |
| [depth_widget](depth_widget/) | Widget | Three pages plus a glance: current depth, maximum, and both together |
| [depth_field](depth_field/) | Data field | Current depth during an activity; records the depth graph into the FIT file |
| [depth_chart](depth_chart/) | Data field | Depth as a chart over time, drawn by the field itself. Shows only — records nothing |
| [depth_gauge](depth_gauge/) | Data field | Depth as a zoned arc in the colour range, drawn by the field itself. Shows only — records nothing |
| [max_depth_field](max_depth_field/) | Data field | Deepest reading of the activity; records a session maximum |

The five apps stay separate Connect IQ projects with their own manifests, app IDs and store listings — the monorepo only shares the source.

| App | Shown as |
| --- | --- |
| `depth_widget` | **Depth** |
| `depth_field` | **Depth** |
| `max_depth_field` | **Max Depth** |
| `depth_chart` | **Depth Chart** |
| `depth_gauge` | **Depth Gauge** |

The directory names are Connect IQ project names and stay in `snake_case`; the app names are what the user reads, in the store, in the launcher and in the data field picker, and are written out properly. The widget and the Depth field share a name on purpose — they are the same thing in two places, and a widget never appears in the same list as a data field.

## This is **not** a dive computer

⚠️ **Do not rely on any of these for safety.**

They are a curiosity for snorkelling and casual swimming, not dive instruments.

- They do no decompression calculation, track no no-decompression limit, and have no ascent rate warning, gas management, or alarm of any kind.
- They have never been checked against a reference depth gauge. There is no calibration procedure and no accuracy figure.
- They fail silently. If the surface pressure baseline is wrong, the depth is wrong, and nothing on screen tells you that.
- The sensor they read was not built to go underwater, and the reading may stop meaning anything after the first metre or so — see below.

Use a real dive computer for anything where the number matters.

## How it works and drawbacks

Connect IQ exposes **no depth API**. Checked against the 9.2.0 API surface, the only depth-related symbol in the entire SDK is `LAP_TRIGGER_DEPTH` — a reason a lap was triggered, not a way to read depth. So depth here is inferred from the barometric pressure sensor, which is there for altitude and weather:

```
depth = (pressure - surface pressure) / pressure per metre of water
```

Three consequences fall out of that.

**The surface pressure has to be guessed.** There is no "you are now at the surface" signal, so the app tracks the lowest pressure seen over a trailing window of the last few minutes and treats that as the surface. The window is frozen while the watch looks submerged, so a long dive cannot drag the baseline down after it. This copes with weather drift and with walking down to the water, and recovers on its own from a bad sample — but if it ever gets the baseline wrong, every reading is offset until it recovers or you re-zero.

Starting while already in the water is the case it cannot detect: the first pressure it sees becomes the surface. The widget re-zeroes with the Start button; the data fields have no input of their own, so they use the **Re-zero depth** setting, which needs the phone and is therefore not reachable mid-activity.

**Water density is a setting, not a measurement.** Fresh water is 9806.65 Pa per metre (ρ=1000). Salt is 10000 Pa per metre, the EN13319 `1 msw` convention that dive computers use. Leaving it set to Fresh in the sea over-reports depth by about 2.5% — half a metre at 20 m.

The [Depth data field](depth_field/) records the raw pressure into the activity precisely so this can be checked: a trace that climbs and then flattens into a hard ceiling regardless of how much deeper you go is the sensor saturating, not the water.

## Settings

These live in Garmin Connect under the app's settings. The first three exist in all five apps:

| Setting | What it does |
| --- | --- |
| Water type | Fresh or salt, which sets the pressure per metre used above |
| Units | Metres, feet, or follow the watch's elevation unit |
| Re-zero depth | Discards the baseline and the maximum and starts over. Switches itself back off. |
| Colour range | Widget, Depth Chart and Depth Gauge — which depths the colour scale spans. See below. |

### Colour range

The widget and its glance colour the reading blue, then green, yellow and red as it gets deeper, so a glance at it says roughly how deep you are without reading the number. That only works if the bands cover the range you actually swim: at a freediver's scale a snorkeller never leaves the first band and the colour tells them nothing at all.

| Profile | Blue | Green | Yellow | Red |
| --- | --- | --- | --- | --- |
| **Snorkel** (default) | < 2 m | 2–5 m | 5–10 m | ≥ 10 m |
| | < 7 ft | 7–16 ft | 16–33 ft | ≥ 33 ft |
| Freedive | < 10 m | 10–20 m | 20–30 m | ≥ 30 m |
| | < 33 ft | 33–66 ft | 66–98 ft | ≥ 98 ft |
| Deep | < 20 m | 20–40 m | 40–60 m | ≥ 60 m |
| | < 66 ft | 66–131 ft | 131–197 ft | ≥ 197 ft |

A band edge is one depth shown two ways, not two sets of thresholds. The feet are the metres rounded, and the profile means the same physical depth whichever unit you display — a colour scale that moved when you switched units would be a different scale, not the same one in other words. Each edge belongs to the deeper band: at exactly 2 m the snorkel profile is already green.

Both unit systems are spelled out in the setting itself because the list is rendered by the phone, which has no way to know what Units is set to.

The Depth and Max Depth fields have no colour of their own — a `SimpleDataField` hands the system a string and the system draws it — so the setting does not appear in those two.

## The two drawn fields

Depth and Max Depth are `SimpleDataField`s: they hand the system a string and the system draws it. Depth Chart and Depth Gauge are full `DataField`s, which get the field area and an `onUpdate(dc)` and do everything themselves.

They are **two apps rather than one app with a Style setting**. A data field is picked from a list on the watch, and that list has one entry per app — so a setting could only be reached after the field was already on a data screen, and there was no way to put a chart on one screen and a gauge on another. Two entries in the picker takes two apps. Both are still one codebase: everything they share lives in the barrel.

Neither records anything. The per-record depth series and the raw pressure belong to the Depth field and the session maximum to Max Depth; writing them here as well would duplicate the whole graph in Garmin Connect for anyone running two of these at once. Pair one with the Depth field if the activity should carry the data as well as show it.

### Depth Chart

Laid out like the watch's own barometer field: the reading across the top, and under it the last two minutes of depth as a **solid body of water** hanging from a surface line, deepening downwards.

The fill is the point. The barometer field fills the area between its axis and its trace, and the same fill means something here — depth is measured down from the surface, so the block between the surface line and the trace *is* the reading, and the chart reads as water rather than as a line. It is banded blue, green, yellow and red as it deepens, at the profile's own boundaries, so the fill carries the same colour information the reading does and the bands can be read as a scale.

**The bottom of the chart is the session maximum.** The chart scales to the deepest the session has been rather than to fixed steps, so the maximum is the floor of the picture — an orange line along the bottom with `MAX` and the depth on it. There is one reference on the chart, not two, which is what the fixed steps got wrong: a line floating in the middle reads as a threshold or an average just as readily as a maximum.

The cost of that is a chart that rescales as the maximum grows instead of holding still. A shallow session is floored at 0.5 m, which is already inside the band the model treats as "at the surface" — otherwise a two-centimetre maximum would stretch sensor noise across the whole field.

### Depth Gauge

The upper half of a zone gauge, like the watch's own heart rate one: the colour profile's four bands as a scale, with the reading in the middle of it.

It is drawn **two ways**, because a data field can be handed anything from the whole screen to a band a few rows tall and one shape does not serve both:

| Field | Shape |
| --- | --- |
| Full screen, top half, bottom half | An **arc concentric with the display**, running right along the bezel like the built-in gauges |
| Everything else | A **bar** along the bottom, reading above it |

The arc is only ever concentric with the display, never fitted into the field: an arc on the lens's own centre is on the lens at every point, however large. Where the field stops short of the lens's diameter — a two-field top half is 129 rows tall on a 260-row screen — the **sweep** is trimmed by a couple of degrees rather than the radius, so the arc stays on the bezel. That is worth 254 px of a 260 px field, against about 156 for a fitted semicircle.

The bar takes everything else. A semicircle is limited by the field's *height*, so in a four-field band 65 rows tall it would span about a third of the width and squeeze the reading into what was left — backwards, since the reading is the point and the gauge is context around it. The bar uses the whole width and leaves the reading a real font size.

The zones come from the same numbers `depthColor()` colours by, so the gauge and the reading cannot disagree about what colour a depth is. The current depth is a bright **arrowhead** riding on the band; the session maximum is an orange **tick straight across** it, with `MAX` and the depth under the reading when there is room. Two different shapes on purpose — a second arrowhead would read as a second current reading, and a short arc in another colour would read as one more zone.

The gauge runs to one zone-width past the red boundary — 15 m on Snorkel, 40 m on Freedive, 80 m on Deep — because a gauge that pins the moment it turns red says nothing after that.

### Round screens

Every device in the product lists is round, and a data field is handed a rectangle regardless: a field along the top edge has both its top corners cut away, and its topmost row is one pixel wide. Drawing to the whole rectangle puts the label in the bezel.

Both fields therefore measure where they are before drawing — from their size and `getObscurityFlags()`, which is enough because the system tiles the fields — and then work with the lens rather than against it: the chart places its heading below the rows the lens has pinched away and fills its water column by column out to the curve, and the gauge puts its arc concentric with the display so it follows the bezel exactly.

That geometry is `DepthFieldLayout` in the barrel, shared by both and [documented there](DepthCore/README.md#drawing-on-a-round-screen), with unit tests — it is not something you can check by eye without a watch, and the tests already caught one off-by-one that handed back a pixel a fraction outside the lens.

## Icons

Two launcher icons between the five apps, both the same disc of water split by the wave of the surface:

| Icon | Apps | Arrow |
| --- | --- | --- |
| `resources/depth_icon.svg` | Depth, Depth Chart, Depth Gauge, the widget | Runs on down into the deep |
| `resources/depth_icon_max.svg` | Max Depth | Stops on a floor line |

Everything but the arrow is shared, so the family reads as one product at 40 px while Max Depth is still tellable from Depth — which matters, because those two sit next to each other in the data field picker.

`resources/` holds the masters and is **not** in the repository (`.gitignore` excludes it, along with the store artwork). Each app ships its own byte-for-byte copy at `resources/drawables/launcher_icon.svg`, and those are what actually build. Copy a master over them rather than editing in place; they are expected to be identical to it.

## Building

Requires the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) (developed against 9.2.0) and a developer key.

Build a project from its own directory — the barrel is picked up from `base.barrelPath` in each `monkey.jungle`, so no separate step is needed:

```sh
cd depth_field
monkeyc -f monkey.jungle -o depth_field.prg -y /path/to/developer_key -d fenix7
```

Building any of the four data fields prints a `(:glance) annotation will be ignored` warning per annotated declaration in the barrel, and a launcher icon warning about the 128 px source being scaled to the device's size. All of them are expected and harmless — see [DepthCore/README.md](DepthCore/README.md#two-things-worth-knowing) for the first and [`resources/depth_icon.svg`](resources/) for the second.

The shared model and the field layout have unit tests, run against the barrel on its own — see [DepthCore/README.md](DepthCore/README.md#tests).

**Keep the developer key outside this repository.** `.gitignore` covers the usual names, but the safest place is a directory that is not the working tree at all.

See the [Connect IQ basics](https://developer.garmin.com/connect-iq/connect-iq-basics/) for setting up the SDK in the first place.

## Languages

All five apps ship in **English, German, French, Italian and Spanish**. Every string the user sees comes from resources — the settings, the widget and glance labels, the re-zero confirmation and the data field labels — so adding another is a resource-only change:

1. Copy `resources/strings/strings.xml` to `resources-<lang>/strings/strings.xml` in the project and translate the values, keeping the `id`s. Use Garmin's code for `<lang>`: `deu`, `fre`, `ita`, `spa`, `por`, `dut`, `nob`, and so on — the full list is in `bin/projectInfo.xml` in the SDK.
2. Add the language to `<iq:languages>` in that project's `manifest.xml`. Without this the build prints `String resources will be ignored` and the folder is skipped entirely.
3. Repeat per project — the five are separate Connect IQ apps and do not share resources.

Four things to know before translating:

- **Declare every id, including `AppName`.** A missing string does not silently fall back to English: the build warns `String id 'AppName' undefined for language 'deu'` and the app has no name in that language. `AppName` is repeated verbatim rather than translated, on purpose — it is the app's identity in the store and in the launcher, not a label.

- **The widget labels are drawn into fixed slots on a round screen.** `LabelDepth`, `LabelMax` and `LabelMaxDepth` are centred at a set size and will be clipped, not wrapped, if a translation runs long. The English is already abbreviated for the summary page for exactly this reason. The glance labels are measured at run time and can be any length.
- **The glance strings carry `scope="glance"`.** Without it the resource is not visible from glance code and the build fails with `Value 'Rez' not available in all function scopes`. Keep the attribute when copying.
- **Units are not translated.** `m` and `ft` are appended in code rather than baked into the labels, so a translation is one word and cannot get the symbols wrong. The band edges in the colour range list are numerals in both systems and stay as they are. The `n/a` shown when there is no reading comes from the barrel, which ships no resources of its own, and also stays as it is.

The shipped translations have been compiled but not seen on a watch: the on-screen labels in particular are the ones to check for clipping, since the accented capitals (`PROFONDITÀ`, `PROF. MÁX`) depend on the device font's glyph coverage.

### Running in the emulator

- Open the project directory you want to run — the five are separate Connect IQ projects, so VS Code needs the one, not the repository root.
- Make sure one of its source files (in `source`, with the `.mc` extension) is open and selected in the editor.
- Select `Run > Run Without Debugging` (`Command + F5` on Mac, `Ctrl + F5` elsewhere).
- Pick a product from the list you are prompted with.

> ℹ Note: The emulator cannot dive. It reports no pressure at all until
> `Simulation > Activity Data` is set to `Data Simulation`, and what that
> generates sits at a fixed altitude and never enters the water. Playing a FIT
> file does not help: the emulator does not carry the recorded pressure into
> `Activity.Info`.

### Side loading onto a watch

- Plug the watch into your computer.
- `Command + Shift + P` (`Ctrl + Shift + P` elsewhere) to summon the command palette.
- Type "Build for Device" and select `Monkey C: Build for Device`.
- Select the product to build for. An empty menu means no valid devices are configured for the project.
- Choose an output directory.
- Copy the generated `PRG` file to the watch's `GARMIN/APPS` directory.
