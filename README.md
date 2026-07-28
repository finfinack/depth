# Depth

Barometric depth for Garmin watches (Fenix, Epix, Tactix) — a widget, two data fields, and the model they share.

Find them on the [Garmin ConnectIQ store](https://apps.garmin.com/developer/1e45545b-eec0-40b0-886d-61739dd6f510/apps) for free to install them.

Previously three separate repositories. They are one now because all three carried an identical copy of the depth model, and keeping three copies in step by hand was the main source of drift.

| Project | Type | What it is |
| --- | --- | --- |
| [DepthCore](DepthCore/) | Monkey Barrel | The depth model, colour scale and FIT helpers. No UI. |
| [depth_widget](depth_widget/) | Widget | Three pages plus a glance: current depth, maximum, and both together |
| [depth_field](depth_field/) | Data field | Current depth during an activity; records the depth graph into the FIT file |
| [depth_graph](depth_graph/) | Data field | Depth as a chart over time or as a zoned gauge, drawn by the field itself. Shows only — records nothing |
| [max_depth_field](max_depth_field/) | Data field | Deepest reading of the activity; records a session maximum |

The four apps stay separate Connect IQ projects with their own manifests, app IDs and store listings — the monorepo only shares the source.

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

These live in Garmin Connect under the app's settings. The first three exist in all four apps:

| Setting | What it does |
| --- | --- |
| Water type | Fresh or salt, which sets the pressure per metre used above |
| Units | Metres, feet, or follow the watch's elevation unit |
| Re-zero depth | Discards the baseline and the maximum and starts over. Switches itself back off. |
| Colour range | Widget and the graph field — which depths the colour scale spans. See below. |
| Style | Graph field only — Chart or Gauge. See below. |

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

### Style

The graph field draws itself, so it can draw either of two things. One field, one setting, rather than two apps competing for the same slot on a data screen.

**Chart** plots the last two minutes of depth against time, deepening downwards from a surface line at the top, in the style of the watch's own barometric pressure chart. The line takes its colour from the depth it is at, the session maximum crosses it as an orange line, and the bottom edge snaps to fixed steps — 2, 5, 10, 20, 30, 50, 100 m — so the trace holds still instead of creeping every time the maximum gains a centimetre. The value in the corner is what the bottom of the chart is worth.

**Gauge** shows where the current depth sits in the colour range instead, the way a heart rate gauge shows a zone: a bar divided into the four colours at the profile's own boundaries, a marker at the current depth and an orange tick at the session maximum. The zones come from the same numbers `depthColor()` colours by, so the bar and the reading above it cannot disagree.

The gauge runs to one zone-width past the red boundary — 15 m on Snorkel, 40 m on Freedive, 80 m on Deep — because a gauge that pins the moment it turns red says nothing after that.

## Building

Requires the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) (developed against 9.2.0) and a developer key.

Build a project from its own directory — the barrel is picked up from `base.barrelPath` in each `monkey.jungle`, so no separate step is needed:

```sh
cd depth_field
monkeyc -f monkey.jungle -o depth_field.prg -y /path/to/developer_key -d fenix7
```

Building either data field prints two `(:glance) annotation will be ignored` warnings from the barrel. They are expected and harmless — see [DepthCore/README.md](DepthCore/README.md#two-things-worth-knowing).

The shared model has unit tests, run against the barrel on its own — see [DepthCore/README.md](DepthCore/README.md#tests).

**Keep the developer key outside this repository.** `.gitignore` covers the usual names, but the safest place is a directory that is not the working tree at all.

See the [Connect IQ basics](https://developer.garmin.com/connect-iq/connect-iq-basics/) for setting up the SDK in the first place.

## Languages

All four apps ship in **English, German, French, Italian and Spanish**. Every string the user sees comes from resources — the settings, the widget and glance labels, the re-zero confirmation and the data field labels — so adding another is a resource-only change:

1. Copy `resources/strings/strings.xml` to `resources-<lang>/strings/strings.xml` in the project and translate the values, keeping the `id`s. Use Garmin's code for `<lang>`: `deu`, `fre`, `ita`, `spa`, `por`, `dut`, `nob`, and so on — the full list is in `bin/projectInfo.xml` in the SDK.
2. Add the language to `<iq:languages>` in that project's `manifest.xml`. Without this the build prints `String resources will be ignored` and the folder is skipped entirely.
3. Repeat per project — the four are separate Connect IQ apps and do not share resources.

Four things to know before translating:

- **Declare every id, including `AppName`.** A missing string does not silently fall back to English: the build warns `String id 'AppName' undefined for language 'deu'` and the app has no name in that language. `AppName` is repeated verbatim rather than translated, on purpose — it is the app's identity in the store and in the launcher, not a label.

- **The widget labels are drawn into fixed slots on a round screen.** `LabelDepth`, `LabelMax` and `LabelMaxDepth` are centred at a set size and will be clipped, not wrapped, if a translation runs long. The English is already abbreviated for the summary page for exactly this reason. The glance labels are measured at run time and can be any length.
- **The glance strings carry `scope="glance"`.** Without it the resource is not visible from glance code and the build fails with `Value 'Rez' not available in all function scopes`. Keep the attribute when copying.
- **Units are not translated.** `m` and `ft` are appended in code rather than baked into the labels, so a translation is one word and cannot get the symbols wrong. The band edges in the colour range list are numerals in both systems and stay as they are. The `n/a` shown when there is no reading comes from the barrel, which ships no resources of its own, and also stays as it is.

The shipped translations have been compiled but not seen on a watch: the on-screen labels in particular are the ones to check for clipping, since the accented capitals (`PROFONDITÀ`, `PROF. MÁX`) depend on the device font's glyph coverage.

### Running in the emulator

- Open the project directory you want to run — the four are separate Connect IQ projects, so VS Code needs the one, not the repository root.
- Make sure one of its source files (in `source`, with the `.mc` extension) is open and selected in the editor.
- Select `Run > Run Without Debugging` (`Command + F5` on Mac, `Ctrl + F5` elsewhere).
- Pick a product from the list you are prompted with.

A freshly started emulator reports no pressure at all, so every app shows `n/a`
until it is given some. `Simulation > Activity Data` is where that comes from,
either as generated data or as a FIT file — see [testdata/](testdata/) for a
dive profile to load and for what the emulator has and has not been seen to do
with it. The emulator remains the wrong place to judge whether the depth
readings themselves are right; only a watch in the water settles that.

### Side loading onto a watch

- Plug the watch into your computer.
- `Command + Shift + P` (`Ctrl + Shift + P` elsewhere) to summon the command palette.
- Type "Build for Device" and select `Monkey C: Build for Device`.
- Select the product to build for. An empty menu means no valid devices are configured for the project.
- Choose an output directory.
- Copy the generated `PRG` file to the watch's `GARMIN/APPS` directory.
