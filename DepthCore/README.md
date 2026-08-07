# DepthCore

The depth model shared by the app, the widget and the four data fields, packaged as a [Monkey Barrel](https://developer.garmin.com/connect-iq/core-topics/shareable-libraries/).

Before this existed, `depthModel.mc` was copied byte-for-byte into all three projects and `depthColors.mc` into two of them, so every fix to the baseline tracking had to be made three times and kept in step by hand.

| File | What is in it |
| --- | --- |
| `source/depthModel.mc` | `DepthModel` — pressure to depth, the trailing surface-pressure baseline, the maximum, the colour band crossings, and the unit/water-type settings. Also `formatDuration()`, which writes `bottom_time` as "2m 14s" |
| `source/depthColors.mc` | `depthColor()` — the blue/green/yellow/red scale used by the app and its glance, in three selectable depth ranges |
| `source/depthFit.mc` | `depthCentimeters()` — depth to the clamped centimetres the data fields write into the FIT file |
| `source/depthLayout.mc` | `DepthFieldLayout` — where a full `DataField` may draw on a round screen, and the font fitting that goes with it |

`depthLayout.mc` is here for the same reason the model is: Depth Chart and Depth Gauge are two apps with one problem, and a second copy of the lens geometry would drift from the first. See [Drawing on a round screen](#drawing-on-a-round-screen).

## Using it

Each consuming project points at this barrel from its `monkey.jungle`:

```
base.barrelPath = ../DepthCore/monkey.jungle
```

and declares the dependency in its `manifest.xml`:

```xml
<iq:barrels>
  <iq:depends name="DepthCore" version="2.3.3"/>
</iq:barrels>
```

Source files then use `import DepthCore;`.

## Settings it reads

`DepthModel.loadSettings()` reads these property keys, so a consuming app declares the ones it wants the user to control in its own `resources/settings/properties.xml`:

| Key | Type | Default |
| --- | --- | --- |
| `waterType` | number | `0` (fresh) |
| `unitOverride` | number | `0` (follow the watch) |
| `rezero` | boolean | `false` |
| `colorProfile` | number | `0` (snorkel) |
| `bandAlert` | boolean | `true` |
| `diveThreshold` | number | `100` (centimetres, so 1.0 m) |

`rezero` is a one-shot trigger rather than a state: it is acted on once and then switched back off. **Exactly one model per app may consume it**, which is what the constructor's `DepthCore.REZERO_HANDLE` / `REZERO_IGNORE` argument decides. An app with a glance builds two models against one property store, and the glance's is discarded after every draw — so it passes `REZERO_IGNORE` and leaves the trigger for the model the user is actually looking at. There is no default, because there is no answer that is right for both.

`colorProfile` is declared by the app, Depth Chart and Depth Gauge — the three that colour something. Depth and Max Depth are `SimpleDataField`s, which hand the system a string and let it draw, so they leave it out and get the default from the fallback below.

`diveThreshold` is declared by everything that puts a dive count or a bottom time in front of the user: the app, Depth and Max Depth, which record them into the activity, and Depth Gauge, which shows them when the field is big enough. Depth Chart leaves it out — it draws the depth over time and neither counts nor records a dive. `dive_count` and `bottom_time` are tracked by every model regardless, at the default above where the app has not declared the key.

`bandAlert` is declared by the app alone. The model reports a boundary crossing in `band_crossed` for anyone who wants it, and raising an alert on one is the consuming app's business — the buzz itself lives in `depth_app`, not here, because the four data fields can be run together and cannot see each other, so a buzz in the barrel would fire once per field on a data screen.

**A key the app does not declare falls back to the default above.** `Properties.getValue()` throws on an undeclared key, and `DepthModel` is constructed by every app that embeds the barrel — so the exception is caught and treated as "not configured", which is the same situation as a setting left at its default. Without that, adding a setting here would crash every app that had not yet declared it.

## Drawing on a round screen

A `SimpleDataField` hands the system a string and the system finds room for it. A full `DataField` gets a rectangle and an `onUpdate(dc)`, and is on its own — including about the fact that on a round watch a good part of that rectangle is not on the lens. A field along the top edge has both its top corners cut away, and its topmost row is one pixel wide. Almost every device in the product lists is round, so this is the case that matters, not the exception.

The three that are not — Instinct E 40/45 mm and Instinct 3 Solar 45 mm, all semi-octagons — are handled by not handling them: `measure()` sets the radius to 0 for any screen shape other than round or semi-round, and every caller treats a radius of 0 as "there is no lens here", falling back to the plain rectangle. That is deliberate. A semi-octagon is not a circle with a bite out of it, and approximating it with one would put pixels under the bezel while claiming they were safe.

Connect IQ gives a field two clues about its place on the screen and no more: the size of its rectangle, and `getObscurityFlags()`, which says which screen edges that rectangle touches. Between them those pin down the origin for most fields — and from the origin the lens is a circle. Not for all of them, though; see [What the flags cannot tell you](#what-the-flags-cannot-tell-you).

`DepthFieldLayout` turns that into two things drawing code can use:

| | |
| --- | --- |
| `top()`, `bottom()` | the rows worth drawing into at all. Rows narrower than 60% of the field are trimmed off either end, up to a third of the field's height — they are the pinched ends of the lens, where a heading would be clipped to two characters. Without this, a heading drawn at row 0 of a top field disappears completely. |
| `left(from, to)`, `right(from, to)` | the horizontal span inside the lens for **every** row of a band. A band low in the field is wider than one at its top edge, so the heading and the drawing below it each ask about their own rows rather than sharing one inset. |
| `rowLeft(row)`, `rowRight(row)` | the span of a single row, and `columnTop(column)`/`columnBottom(column)` the same turned ninety degrees. For drawing that follows the lens rather than squaring itself off inside it: the chart fills a column of water at a time, and fitting that to a rectangle would throw away most of a corner field. |
| `contains(x, y)` | the same question for one point, without the square root — the chart asks it once per pixel column. |
| `lensCenterX()`, `lensCenterY()`, `lensRadius()` | the lens circle itself, in the field's coordinates. |
| `fontFitting(dc, text, width, height)` | the largest text font that renders `text` inside a box. Both dimensions, because either alone picks a font that does not fit. |

`update(dc, obscurity)` must be called first thing in `onUpdate()` — that is the only place `getObscurityFlags()` is valid. It recomputes only when the field's size or flags change, which in practice is once, since the user cannot move a field mid-activity.

On a screen that is not round the geometry switches off: every row is usable and the span is the full width less a small margin.

**The circle is exposed as well as the rows because not everything drawn is a rectangle.** Depth Gauge draws an arc, and an arc concentric with the lens is on the lens at every point, however large — so it runs right along the bezel like the watch's own zone gauges. Fitting that arc into a rectangle inside the lens instead shrinks it to about half the screen it could have used. Anything that genuinely needs a rectangle uses the rows.

### What the flags cannot tell you

The origin is inferred from the size and the flags: a field touching the low edge of an axis starts at 0, one touching the high edge ends at the screen edge, one touching both spans it. Connect IQ exposes no way to ask a field where it is, so that inference is all there is.

**A field touching neither edge on an axis cannot be placed.** `measure()` assumes it is centred. Checked against the layout rectangles the SDK ships per device, that is exact for the 1-, 2- and 3-field layouts, and wrong for the stacked middle bands of the denser ones — the system stacks those rather than centring them, by up to 2.8× the field's height across 430 of the 963 field rectangles shipped for the devices in the product lists.

The consequence is bounded and one-directional: such a field believes the lens is wider than it is, so its outermost pixels can land under the bezel. It never draws into another field. Depth Gauge's arc is unaffected — every layout that takes the arc touches the top or the bottom, so its position is exact — and it costs the bar and the chart their extreme corners on 4-field-and-denser middle bands only.

There is deliberately **no shared "draw the heading" helper**. The two fields head themselves differently — the chart puts its label and reading on one row above the plot, the gauge centres the reading inside the arc — and a single function covering both would take more arguments than the twenty lines it saved. What is genuinely common is the geometry and the font fitting, and that is what is here.

## Two things worth knowing

**Classes resolve unqualified; free functions and module constants do not.** With `import DepthCore;` in scope, `new DepthModel(...)` compiles. `depthColor(x)` does not — Monkey C resolves an unqualified name against `self` first, and the build fails with `Cannot find symbol ':depthColor' on type 'self'`. The same applies to module-level constants used from inside a class: it is `DepthCore.depthColor(x)`, `DepthCore.depthCentimeters(x)`, `DepthCore.REZERO_HANDLE` and `DepthCore.TREND_LEVEL`.

**`(:glance)` has to stay on the barrel code.** It is a build exclusion applied by the consuming app rather than a barrel annotation, so it needs no `<iq:annotations>` entry and works on barrel code as-is. Removing it fails the app's build with `Value 'DepthModel' not available in all function scopes`.

The cost is that the data fields have no glance, so each one emits a harmless warning per annotated declaration at build time:

```
WARNING: Glance applications are not supported for app type 'datafield' ...
         The (:glance) annotation will be ignored.
```

The annotation being ignored is the correct outcome — a data field includes the code either way. Three copies of the model was the alternative, and a few warnings is the better trade.

There is a second cost, and it only shows up in the editor. VS Code reports errors the compiler does not:

```
epix2: Value 'depthView' not available in all function scopes.
epix2: Value 'initialize' not available in all function scopes.
epix2: Value 'onSettingsChanged' not available in all function scopes.
```

The editor's type checker builds a glance scope for a data field even though the compiler has just said data fields have none, and then cannot find the app's own view class in it. Every device in every product list builds clean from the command line, so the errors are the editor's alone — but they do not go away on their own, and an editor full of red is its own kind of bug. Each data field's `AppBase` subclass therefore carries `(:typecheck(disableGlanceCheck))` on the class, which is where it has to go: the view is named in a member variable as well as in two methods.

`depthFit.mc` is deliberately *not* annotated: the glance displays a reading, it never records one, and glance scope is the tightest memory budget in the project.

## Tests

`test/` holds unit tests for the barrel. They are built by `test.jungle` rather than `monkey.jungle`, so nothing there reaches a watch: `monkey.jungle` sets `base.sourcePath = source`, because barrel code is compiled into every consuming app and anything reachable from it costs memory on the device.

Barrels do not produce a runnable `PRG`, so the SDK's `barreltest` builds the barrel and its tests into one, and the simulator runs it:

```sh
cd DepthCore
barreltest -f test.jungle -d fenix7 -o /tmp/depthcore_test.prg -y /path/to/developer_key -w -l 3
monkeydo /tmp/depthcore_test.prg fenix7 -t   # the simulator has to be running
```

Two things about the test build are not obvious:

- **Every `(:test)` function becomes a test case**, whatever it is named or how it is written. Helpers must not carry the annotation — an annotated helper is run as a test of its own, and one taking arguments errors out.
- **`test/resources/settings/properties.xml` exists because `DepthModel` reads the app settings in its constructor.** A barrel ships no properties of its own, so the test build declares the ones the model reads. Anything left out of it exercises the fallback described under [Settings it reads](#settings-it-reads) instead, which is why `colorProfile` is deliberately missing from it.

### Making time pass

`update()` reads `System.getTimer()` itself, so two calls in a row are microseconds apart — exactly the case the trend and the maximum both refuse to act on. Everything with real risk in this model is about elapsed time: the baseline window rotating, the stale-baseline warning, the trend's commit/release hysteresis, the maximum's run-in test.

So `update(info)` is a one-liner over **`updateAt(info, now)`**, and the tests drive `updateAt` with a synthetic millisecond clock. That is the whole seam — no injected clock object, no test-only branch in the model, and `update()` remains what every app calls.

The model still reads the pressure sensor through `Activity.Info`, which a test constructs directly:

```monkey-c
var info = new Activity.Info();
info.rawAmbientPressure = 110000.0;
model.updateAt(info, 1000);   // 1 s after the previous sample
```

## Versioning

The version in `manifest.xml` and the `<iq:depends>` version in each app must match. Both are `2.3.3`. Bump them together.

It is deliberately the same number as the apps carry in the store rather than a version of its own: the barrel is not published anywhere and has exactly six consumers, all in this repository and all released together, so a separate lineage for it would be two numbers to keep straight in exchange for nothing. The apps' own version is set when uploading to the store — Connect IQ app manifests have no version field.
