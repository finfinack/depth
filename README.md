# Depth

This is a data field for Garmin watches (Fenix, Epix, Tactix) displaying the current water depth.

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
