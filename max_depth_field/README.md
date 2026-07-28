# Depth

This is a data field for Garmin watches (Fenix, Epix, Tactix) displaying the max water depth (since starting the activity).

The unit is shown in the field label (`Max Depth (m)` / `Max Depth (ft)`), because a simple data field has no room for a suffix on the value itself. A new maximum has to be supported by two consecutive readings before it counts, so a single noisy sample cannot latch into it permanently. Settings (water type, units, re-zero) are in Garmin Connect under the app's settings.

## This is not a dive computer

**Do not rely on this app for safety.** It is a curiosity for snorkelling and casual swimming, not a dive instrument.

- It does no decompression calculation, tracks no no-decompression limit, and has no ascent rate warning, gas management, or alarm of any kind.
- It has never been checked against a reference depth gauge. There is no calibration procedure and no accuracy figure.
- It fails silently. If the surface pressure baseline is wrong, the depth is wrong, and nothing on screen tells you that.
- The sensor it reads was not built to go underwater, and the reading may stop meaning anything after the first metre or so — see below.

Use a real dive computer for anything where the number matters.

## How it works, and what that costs

Connect IQ exposes **no depth API**. Checked against the 9.2.0 API surface, the only depth-related symbol in the entire SDK is `LAP_TRIGGER_DEPTH` — a reason a lap was triggered, not a way to read depth. So depth here is inferred from the barometric pressure sensor, which is there for altitude and weather:

```
depth = (pressure - surface pressure) / pressure per metre of water
```

Three consequences fall out of that.

**The surface pressure has to be guessed.** There is no "you are now at the surface" signal, so the app tracks the lowest pressure seen over a trailing window of the last few minutes and treats that as the surface. The window is frozen while the watch looks submerged, so a long dive cannot drag the baseline down after it. This copes with weather drift and with walking down to the water, and recovers on its own from a bad sample — but if it ever gets the baseline wrong, every reading is offset until it recovers. A wrong baseline is worse here than for the current depth, because the maximum keeps the error for the rest of the activity.

Starting the activity while already in the water is the case it cannot detect: the first pressure it sees becomes the surface. Use the **Re-zero depth** setting to start over, which also clears the maximum. It needs the phone, so it is not reachable mid-activity.

**Water density is a setting, not a measurement.** Fresh water is 9806.65 Pa per metre (ρ=1000). Salt is 10000 Pa per metre, the EN13319 `1 msw` convention that dive computers use. Leaving it set to Fresh in the sea over-reports depth by about 2.5% — half a metre at 20 m.

**The sensor may saturate very shallow, and this is untested.** Fenix-class barometers are typically specified to somewhere around 1100 hPa, which is only about a metre of water above sea level pressure. If that limit is real, readings past a metre or two are meaningless, and they will keep looking perfectly plausible while being nothing of the kind. This has not been verified on a real device.

See https://developer.garmin.com/connect-iq/connect-iq-basics/ for some information around how to set up the Garmin SDK, compile and run the app. The following is mostly a copy of one of the [examples on the Garmin Connect IQ developer page](https://developer.garmin.com/connect-iq/connect-iq-basics/your-first-app/#yourfirstconnectiqapp).

## Running the Program

You should be able to run the app from Visual Studio Code in an Emulator:

- Before running the program, make sure you have one of your source files (in the `source` folder with the `.mc` extension) open and selected in the editor.
- Select `Run > Run Without Debugging` (`Command + F5` on Mac, `Ctrl + F5` on other platforms)
- You will be prompted with the list of products your application supports. Select one from the list.

## Side Loading an App

The Monkey C extension provides a wizard to help developers side load an application. The wizard will create an executable (PRG) of the selected project. Here’s how to use it:

- Plug your device into your computer
- Use `Ctrl + Shift + P` (`Command + Shift + P` on the Mac) to summon the command palette
- In the command palette type “Build for Device” and select `Monkey C: Build for Device`
- Select the product you wish to build for. If you are unable to choose a device for which to build (the menu appears empty), it means that there are no valid devices configured for your project.
- Choose a directory for the output and click `Select Folder`
- In your file manager, go to the directory selected in step 4
- Copy the generated `PRG` files to your device’s `GARMIN/APPS` directory
