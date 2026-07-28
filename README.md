# Depth

Barometric depth for Garmin watches (Fenix, Epix, Tactix) — a widget, two data fields, and the model they share.

Previously three separate repositories. They are one now because all three carried an identical copy of the depth model, and keeping three copies in step by hand was the main source of drift.

| Project | Type | What it is |
| --- | --- | --- |
| [DepthCore](DepthCore/) | Monkey Barrel | The depth model, colour scale and FIT helpers. No UI. |
| [depth_widget](depth_widget/) | Widget | Three pages plus a glance: current depth, maximum, and both together |
| [depth_field](depth_field/) | Data field | Current depth during an activity; records the depth graph into the FIT file |
| [max_depth_field](max_depth_field/) | Data field | Deepest reading of the activity; records a session maximum |

The three apps stay separate Connect IQ projects with their own manifests, app IDs and store listings — the monorepo only shares the source.

## This is not a dive computer

**Do not rely on any of these for safety.** They are a curiosity for snorkelling and casual swimming, not dive instruments. There is no decompression calculation, no no-decompression limit, no ascent rate warning, and no alarm of any kind. Nothing here has ever been checked against a reference depth gauge, and it fails silently — if the surface pressure baseline is wrong, the depth is wrong, and nothing on screen says so.

Each project's README has the full detail. Use a real dive computer for anything where the number matters.

## Building

Requires the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) (developed against 9.2.0) and a developer key.

Build a project from its own directory — the barrel is picked up from `base.barrelPath` in each `monkey.jungle`, so no separate step is needed:

```sh
cd depth_field
monkeyc -f monkey.jungle -o depth_field.prg -y /path/to/developer_key -d fenix7
```

In VS Code, open a project directory and use `Monkey C: Build for Device` as usual.

Building either data field prints two `(:glance) annotation will be ignored` warnings from the barrel. They are expected and harmless — see [DepthCore/README.md](DepthCore/README.md#two-things-worth-knowing).

**Keep the developer key outside this repository.** `.gitignore` covers the usual names, but the safest place is a directory that is not the working tree at all.
