# Depth (widget)

The same program as [the app](../depth_app/), built as a `widget` instead of a `watch-app`.

> ⚠️ **This is not a dive computer.** Do not rely on it for safety. See the [repository README](../README.md#this-is-not-a-dive-computer) for what that means, and [how it works](../README.md#how-it-works-and-drawbacks) for why the number can be wrong.

What it shows and how to read it is [documented with the app](../depth_app/README.md) — the pages, the [gauge ring](../depth_app/README.md#the-gauge-ring), the [depth buzz](../depth_app/README.md#the-depth-buzz), the trend indicator. All of it is here too, because it is the same code. This file is only about the two things that are not the same.

## No source of its own

There is no `source/` and no `resources/` in this directory, and that is deliberate. `monkey.jungle` points `sourcePath`, `resourcePath` and the four language paths at `../depth_app/`, so both projects compile the same `.mc` files, the same settings and the same translations, and a change to either arrives in both without anyone having to remember the second one. It is the [DepthCore barrel](../DepthCore/)'s reasoning one level up: two copies of the same program is how the two of them drift apart.

`depth_app` holds the files because that is where they already were. Neither project is the real one.

The jungle has to name every path the SDK's default jungle sets, including one line per language, because there is no default that could find another project's directory. **A language added to `depth_app` needs its line here as well** — without it this builds clean and ships untranslated. See [Languages](../README.md#languages).

What is actually in this directory is a manifest, and it differs from the app's in exactly two attributes:

| | `depth_app` | `depth_widget` |
| --- | --- | --- |
| `type` | `watch-app` | `widget` |
| `id` | `aa7e7d36-…` | `2fd1020a-…` |

The ID is the widget's own, from before it was [converted to an app](../README.md#widget-and-app) — so this is an update to the store listing that already exists rather than a second one.

## Two app IDs, two of everything scoped to one

Connect IQ scopes a great deal by app ID, and the widget and the app have different ones. That is not a quirk of this pair: it is the same thing the [settings section](../README.md#settings) already warns about across the other projects.

- **Separate settings.** Water type, units, colour range, dive threshold — set in Garmin Connect under this entry, and setting them on the app does not set them here.
- **Separate Last Session.** `Application.Storage` is per app ID, so each remembers its own last outing and neither can see the other's.

**Install one of the two, not both.** Nothing breaks if both are on the watch, but they will disagree about their settings and their history, and [the depth buzz](../depth_app/README.md#the-depth-buzz) would fire once from each — the same reason only one data field records the depth series.

## Building

Exactly as [the others](../README.md#building), from this directory:

```sh
cd depth_widget
monkeyc -f monkey.jungle -o depth_widget.prg -y /path/to/developer_key -d fenix7
```

The relative paths in `monkey.jungle` are resolved against this directory, so `depth_app/` and `DepthCore/` have to be their siblings — building from a copy of this directory on its own will not work.

It builds with the same single launcher icon warning the app does, and — unlike the four data fields — none of the barrel's `(:glance) annotation will be ignored` ones: a widget has a glance, so the annotations are honoured rather than dropped.
