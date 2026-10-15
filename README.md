# Nameplate

Your Mac's particulars, always in view. Nameplate shows the computer name, model, serial number, chip, memory, graphics, macOS version, current user, uptime, disk space and the full network setup — on the desktop, in the menu bar, in Shortcuts and in Terminal. It updates the moment something changes: switch Wi-Fi networks, plug in Ethernet or connect a VPN and the new addresses appear right away.

It works the way Particulars does, and adds a few things: a public IP lookup (off by default), Wi-Fi signal and channel, a JSON copy, and an installer package for deploying it to many Macs.

## Install

You need macOS 13 Ventura or newer and Apple's free developer tools.

1. Open Terminal and check for the developer tools:

   ```
   xcode-select -p
   ```

   If that prints an error instead of a path, run `xcode-select --install`, click Install, and wait for it to finish.

2. Download Nameplate and build it:

   ```
   git clone https://github.com/mmzeller/nameplate.git ~/Nameplate
   bash ~/Nameplate/build.sh
   ```

   That compiles Nameplate, puts it in Applications, links the `nameplate` Terminal command, and starts it. The first build takes a minute or two. Settings open the first time it runs.

Other options: `build.sh --no-install` (just build), `build.sh --pkg` (also make an installer package), `build.sh --universal` (Apple silicon + Intel in one app; needs the full Xcode app).

## The four ways to use it

**Desktop.** The information sits on your wallpaper, under your icons and windows, on every Space and (optionally) every display. It doesn't change your wallpaper and the mouse goes straight through it. Choose the corner, margins, font, size, weight, color, opacity and shadow under Settings › Desktop. The default corner is bottom left, which stays clear of macOS desktop widgets.

**Menu bar.** Click the icon for a panel with everything in it. Drag the panel away from the menu bar and it stays open as its own little window. Right-click (or Control-click) for a menu: copy everything, copy as JSON, copy any single value, show or hide the desktop text, Settings, Quit. The icon can instead show your IP address or computer name.

**Keyboard.** ⌃⌥⌘C copies everything to the clipboard from anywhere (you'll hear a tick). You can change it or add one that opens the panel, under Settings › General.

**Terminal and Shortcuts.**

```
nameplate                  # everything, readable
nameplate --get ip         # one value
nameplate -g serial -g model
nameplate --json           # everything as JSON
nameplate --keys           # every key and its current value
nameplate --public-ip      # include the public IP
```

Useful keys: `computer-name`, `model`, `model-id`, `serial`, `uuid`, `chip`, `memory`, `gpu`, `os`, `os-version`, `os-build`, `user`, `uptime`, `boot-time`, `disk`, `disk-free`, `disk-used-percent`, `ip`, `subnet`, `router`, `dns`, `mac`, `ssid`, `interface`, `public-ip`, plus per-interface keys like `en0.ip` and `en0.mac`.

In the **Shortcuts** app, add a **Run Shell Script** action containing `/usr/local/bin/nameplate --get ip` (or any key, or `--json` and then **Get Dictionary from Input**). The output flows into the next action like any other text.

## The Wi-Fi network name

Since macOS Sonoma, apps only get the Wi-Fi network name if they're allowed to use Location Services. Nameplate asks once, the first time it runs. It never reads or stores your location. If you said no, turn Nameplate on in System Settings › Privacy & Security › Location Services; everything else works either way.

## What leaves your Mac

Nothing, unless you turn on **Public IP address**. Then Nameplate asks api.ipify.org for your public address when your network changes and every 15 minutes.

## Lab mode and managed Macs

Every setting is an ordinary preference in the `com.mmzeller.Nameplate` domain, so you can set it for everyone:

```
sudo defaults write /Library/Preferences/com.mmzeller.Nameplate LabMode -bool true
sudo defaults write /Library/Preferences/com.mmzeller.Nameplate DesktopPosition topRight
```

**Lab mode** locks Settings, removes the right-click menu (and with it Quit), and keeps the panel's Settings button hidden. Turn it off with `sudo defaults delete /Library/Preferences/com.mmzeller.Nameplate LabMode`.

Settings delivered by a **configuration profile** (NinjaOne, Jamf, Intune and so on) are locked and greyed out in Settings even without lab mode.

| Key | Values |
|---|---|
| `LabMode` | `true` / `false` |
| `LaunchAtLogin` | `true` / `false` (applied at launch when managed or in lab mode) |
| `ShowOnDesktop`, `ShowMenuBarIcon`, `ShowDockIcon` | `true` / `false` |
| `DesktopPosition` | `topLeft`, `topRight`, `bottomLeft`, `bottomRight` |
| `DesktopScreens` | `main`, `all` |
| `DesktopMarginX`, `DesktopMarginY` | points, e.g. `28` |
| `FontFamily` | `System`, `System Monospaced`, `System Rounded`, or any installed family |
| `FontSize` | e.g. `12` |
| `FontWeight` | `light`, `regular`, `medium`, `semibold`, `bold` |
| `TextColor` | `light`, `dark`, `custom` (with `CustomTextColor` = `#RRGGBB`) |
| `TextOpacity` | `0.2` – `1` |
| `TextShadow`, `ShowLabels`, `ShowSectionTitles` | `true` / `false` |
| `InterfaceScope` | `primary`, `active` |
| `VolumeScope` | `startup`, `local`, `all` |
| `MenuBarStyle` | `icon`, `iconAndIP`, `ip`, `name` |
| `CopyHotKey`, `PanelHotKey` | `none`, `ctrlOptCmdC`, `ctrlOptCmdI`, `ctrlOptCmdN`, `ctrlOptCmdP`, `shiftOptCmdI` |
| `Show.<item>` | `true` / `false` for each item: `computerName`, `hostName`, `model`, `modelIdentifier`, `serialNumber`, `hardwareUUID`, `chip`, `memory`, `graphics`, `os`, `server`, `user`, `uptime`, `bootTime`, `disks`, `interfaces`, `ipv4`, `subnetMask`, `router`, `configMethod`, `ipv6`, `macAddress`, `dns`, `searchDomains`, `wifiName`, `wifiSignal`, `publicIP` |

### Deploying with NinjaOne

1. On your Mac, run `bash ~/Nameplate/build.sh --pkg --universal` (or without `--universal` if every Mac has the same kind of chip).
2. Upload `~/Nameplate/build/Nameplate-1.0.pkg` to NinjaOne and install it with a software deployment or a script that runs `installer -pkg Nameplate-1.0.pkg -target /`. The package installs to /Applications, links the `nameplate` command, and starts Nameplate for whoever is signed in.
3. Push any preferences with a script running as root (the `defaults write /Library/Preferences/...` lines above) or a configuration profile.

The app is signed "ad hoc" rather than with an Apple Developer certificate. Installed by a package or script, it runs normally. If you copy the .app to another Mac by hand, macOS may refuse to open it the first time; right-click it and choose Open, or clear the flag with `xattr -dr com.apple.quarantine /Applications/Nameplate.app`.

## Update

```
bash ~/Nameplate/update.sh
```

That gets the latest code from GitHub, rebuilds it, quits the running copy, replaces it and starts it again. Your settings are kept. Rebuilding changes the ad hoc signature, so macOS may ask again about Location Services.

## Uninstall

Quit Nameplate (right-click the menu bar icon › Quit), then:

```
rm -rf /Applications/Nameplate.app
sudo rm -f /usr/local/bin/nameplate
defaults delete com.mmzeller.Nameplate
```

Turn off **Launch at login** first if you'd switched it on, or remove Nameplate from System Settings › General › Login Items.

## How it's put together

- `Sources/NameplateCore` reads the system: `sysctl` and the I/O Registry for hardware, the System Configuration dynamic store (what `scutil` reads) for the network, CoreWLAN for Wi-Fi, and the file system for disks. Both the app and the command-line tool use it.
- `Sources/Nameplate` is the app: desktop windows, the menu bar panel, Settings, keyboard shortcuts, and the change watcher.
- `Sources/NameplateCLI` is the `nameplate` command.
