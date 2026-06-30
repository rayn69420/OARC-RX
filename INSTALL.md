# Installation Guide

## Download From GitHub Releases

1. Open the [Releases page](https://github.com/rayn69420/oarc-rx/releases).
2. Download the latest `oarc-rx_*.zip` asset.
3. Copy the zip into your Factorio mods folder:
   `C:\Users\<your-user>\AppData\Roaming\Factorio\mods`
4. Start Factorio and enable `oarc-rx` in the Mods menu.
5. Restart the game if Factorio asks for it.

## Install From The Factorio Mod Portal

1. Open the [OARC-RX Mod Portal page](https://mods.factorio.com/mod/oarc-rx).
2. Download or subscribe through your usual Factorio/portal flow.
3. Make sure `oarc-rx` is enabled in the Mods menu.

## Steam Version Notes

The Steam edition uses the same writable mods folder:
`%AppData%\Factorio\mods`

You can paste that path directly into the Windows Explorer address bar.

## Important: Remove The Old Mod

Do not keep `OARC_hidden_relic` enabled at the same time as `oarc-rx`.

If both are enabled, Factorio can fail during load with duplicate script command errors such as:
`A script command already exists with the name: tree`

If you previously tested the older fork:

1. Disable `OARC_hidden_relic` in the Mods menu.
2. Remove older `OARC_hidden_relic_*.zip` files from `%AppData%\Factorio\mods` if you no longer need them.

## Installing A Local Build From This Repository

1. Run `package_mod.bat`.
2. The script builds `build\oarc-rx_<version>.zip` using the version from `info.json`.
3. The script also copies the finished zip into your local Factorio mods folder automatically.

## Updating

1. Download the newest `oarc-rx_*.zip` from GitHub Releases.
2. Replace the old zip in `%AppData%\Factorio\mods`.
3. Start Factorio and let it sync mod changes.

## Bug Reports

Please report bugs and issues here:
[https://github.com/rayn69420/oarc-rx/issues](https://github.com/rayn69420/oarc-rx/issues)
