# Depth

Barometric depth for Garmin watches (Fenix, Epix, Tactix) — a widget, two data fields, and the model they share.

Find them on the [Garmin ConnectIQ store](https://apps.garmin.com/developer/1e45545b-eec0-40b0-886d-61739dd6f510/apps) for free to install them.

Previously three separate repositories. They are one now because all three carried an identical copy of the depth model, and keeping three copies in step by hand was the main source of drift.

| Project | Type | What it is |
| --- | --- | --- |
| [DepthCore](DepthCore/) | Monkey Barrel | The depth model, colour scale and FIT helpers. No UI. |
| [depth_widget](depth_widget/) | Widget | Three pages plus a glance: current depth, maximum, and both together |
| [depth_field](depth_field/) | Data field | Current depth during an activity; records the depth graph into the FIT file |
| [max_depth_field](max_depth_field/) | Data field | Deepest reading of the activity; records a session maximum |

The three apps stay separate Connect IQ projects with their own manifests, app IDs and store listings — the monorepo only shares the source.

## This is **not** a dive computer

⚠️ **Do not rely on any of these for safety.**

They are a curiosity for snorkelling and casual swimming, not dive instruments.

- They do no decompression calculation, track no no-decompression limit, and have no ascent rate warning, gas management, or alarm of any kind.
- They have never been checked against a reference depth gauge. There is no calibration procedure and no accuracy figure.
- They fail silently. If the surface pressure baseline is wrong, the depth is wrong, and nothing on screen tells you that.
- The sensor they read was not built to go underwater, and the reading may stop meaning anything after the first metre or so — see below.

Use a real dive computer for anything where the number matters.

## How it works, and what that costs

Connect IQ exposes **no depth API**. Checked against the 9.2.0 API surface, the only depth-related symbol in the entire SDK is `LAP_TRIGGER_DEPTH` — a reason a lap was triggered, not a way to read depth. So depth here is inferred from the barometric pressure sensor, which is there for altitude and weather:

```
depth = (pressure - surface pressure) / pressure per metre of water
```

Three consequences fall out of that.

**The surface pressure has to be guessed.** There is no "you are now at the surface" signal, so the app tracks the lowest pressure seen over a trailing window of the last few minutes and treats that as the surface. The window is frozen while the watch looks submerged, so a long dive cannot drag the baseline down after it. This copes with weather drift and with walking down to the water, and recovers on its own from a bad sample — but if it ever gets the baseline wrong, every reading is offset until it recovers or you re-zero.

Starting while already in the water is the case it cannot detect: the first pressure it sees becomes the surface. The widget re-zeroes with the Start button; the data fields have no input of their own, so they use the **Re-zero depth** setting, which needs the phone and is therefore not reachable mid-activity.

**Water density is a setting, not a measurement.** Fresh water is 9806.65 Pa per metre (ρ=1000). Salt is 10000 Pa per metre, the EN13319 `1 msw` convention that dive computers use. Leaving it set to Fresh in the sea over-reports depth by about 2.5% — half a metre at 20 m.

**The sensor may saturate very shallow, and this is untested.** Fenix-class barometers are typically specified to somewhere around 1100 hPa, which is only about a metre of water above sea level pressure. If that limit is real, readings past a metre or two are meaningless, and they will keep looking perfectly plausible while being nothing of the kind. This has not been verified on a real device.

The [Depth data field](depth_field/) records the raw pressure into the activity precisely so this can be checked: a trace that climbs and then flattens into a hard ceiling regardless of how much deeper you go is the sensor saturating, not the water.

## Settings

The same three settings exist in all three apps, in Garmin Connect under the app's settings:

| Setting | What it does |
| --- | --- |
| Water type | Fresh or salt, which sets the pressure per metre used above |
| Units | Metres, feet, or follow the watch's elevation unit |
| Re-zero depth | Discards the baseline and the maximum and starts over. Switches itself back off. |

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

### Running in the emulator

- Open the project directory you want to run — the three are separate Connect IQ projects, so VS Code needs the one, not the repository root.
- Make sure one of its source files (in `source`, with the `.mc` extension) is open and selected in the editor.
- Select `Run > Run Without Debugging` (`Command + F5` on Mac, `Ctrl + F5` elsewhere).
- Pick a product from the list you are prompted with.

### Side loading onto a watch

- Plug the watch into your computer.
- `Command + Shift + P` (`Ctrl + Shift + P` elsewhere) to summon the command palette.
- Type "Build for Device" and select `Monkey C: Build for Device`.
- Select the product to build for. An empty menu means no valid devices are configured for the project.
- Choose an output directory.
- Copy the generated `PRG` file to the watch's `GARMIN/APPS` directory.
