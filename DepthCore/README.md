# DepthCore

The depth model shared by the widget and both data fields, packaged as a [Monkey Barrel](https://developer.garmin.com/connect-iq/core-topics/shareable-libraries/).

Before this existed, `depthModel.mc` was copied byte-for-byte into all three projects and `depthColors.mc` into two of them, so every fix to the baseline tracking had to be made three times and kept in step by hand.

| File | What is in it |
| --- | --- |
| `source/depthModel.mc` | `DepthModel` — pressure to depth, the trailing surface-pressure baseline, the maximum, and the unit/water-type settings |
| `source/depthColors.mc` | `depthColor()` — the blue/green/yellow/red scale used by the widget and its glance |
| `source/depthFit.mc` | `depthCentimeters()` — depth to the clamped centimetres the data fields write into the FIT file |

## Using it

Each consuming project points at this barrel from its `monkey.jungle`:

```
base.barrelPath = ../DepthCore/monkey.jungle
```

and declares the dependency in its `manifest.xml`:

```xml
<iq:barrels>
  <iq:depends name="DepthCore" version="1.0.0"/>
</iq:barrels>
```

Source files then use `import DepthCore;`.

## Two things worth knowing

**Classes resolve unqualified, bare functions do not.** With `import DepthCore;` in scope, `new DepthModel()` compiles. `depthColor(x)` does not — Monkey C resolves an unqualified call against `self` first, and the build fails with `Cannot find symbol ':depthColor' on type 'self'`. Free functions from the barrel have to be called as `DepthCore.depthColor(x)` and `DepthCore.depthCentimeters(x)`.

**`(:glance)` has to stay on the barrel code.** It is a build exclusion applied by the consuming app rather than a barrel annotation, so it needs no `<iq:annotations>` entry and works on barrel code as-is. Removing it fails the widget build with `Value 'DepthModel' not available in all function scopes`.

The cost is that the two data fields have no glance, so each one emits a harmless warning per annotated declaration at build time:

```
WARNING: Glance applications are not supported for app type 'datafield' ...
         The (:glance) annotation will be ignored.
```

The annotation being ignored is the correct outcome — a data field includes the code either way. Three copies of the model was the alternative, and two warnings is the better trade.

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
- **`test/resources/settings/properties.xml` exists because `DepthModel` reads the app settings in its constructor**, and `Properties.getValue()` on a key that was never declared throws. A barrel ships no properties of its own, so the test build declares its own copy. Keep it in step with each app's `resources/settings/properties.xml`.

What is *not* covered is anything that depends on time passing: `update()` reads `System.getTimer()` itself, so two calls in a row are microseconds apart — exactly the case the trend and the maximum both refuse to act on. The baseline window, the submerged watchdog and the trend thresholds therefore still need the simulator.

## Versioning

The version in `manifest.xml` and the `<iq:depends>` version in each app must match. Both are `1.0.0`. Bump them together.
