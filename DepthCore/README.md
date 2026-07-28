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

## Versioning

The version in `manifest.xml` and the `<iq:depends>` version in each app must match. Both are `1.0.0`. Bump them together.
