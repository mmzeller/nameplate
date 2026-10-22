# Nameplate

Your Mac's particulars, always in view. Nameplate shows the computer name, model, serial number, chip, memory, graphics, macOS version, current user, uptime, disk space and the full network setup — on the desktop, in the menu bar, in Shortcuts and in Terminal. It updates the moment something changes: switch Wi-Fi networks, plug in Ethernet or connect a VPN and the new addresses appear right away.

It works the way Particulars does, and goes further: you can rearrange and rename every line, add your own text and command output, show live CPU, memory, battery and network traffic, give it a background panel, drag it anywhere, put your own text in the menu bar, and record any keyboard shortcut.

## Install

Open Terminal (in Applications › Utilities) and paste:

```
bash <(curl -fsSL https://raw.githubusercontent.com/mmzeller/nameplate/main/install.sh)
```

That downloads the latest version, puts it in Applications and starts it. At the end it offers to add the `nameplate` Terminal command, which needs your Mac password. Settings open the first time Nameplate runs.

**Prefer clicking?** Download **Nameplate.dmg** from the [latest release](https://github.com/mmzeller/nameplate/releases/latest), open it and drag Nameplate into Applications. The first time you open it, macOS says it can't verify the app, because it isn't signed with a paid Apple developer certificate. Click **Done**, open **System Settings › Privacy & Security**, scroll down and click **Open Anyway**. The Terminal command above skips that step.

Works on Apple silicon and Intel Macs with macOS 13 Ventura or newer.

## The four ways to use it

**Desktop.** The information sits on your wallpaper, under your icons and windows, on every Space and (optionally) every display. It doesn't change your wallpaper and the mouse goes straight through it. The default corner is bottom left, which stays clear of macOS desktop widgets.

**Menu bar.** Click the icon for a panel with everything in it. Drag the panel away from the menu bar and it stays open as its own little window. Right-click (or Control-click) for a menu: copy everything, copy as JSON, copy your IP or any single value, show or hide the desktop text, move it, Settings, Quit.

**Keyboard.** ⌃⌥⌘C copies everything to the clipboard from anywhere (you'll hear a tick). Change it, or add shortcuts to copy your IP, open the panel, or show and hide the desktop info, under Settings › Shortcuts.

**Terminal and Shortcuts.**

```
nameplate                  # everything, readable
nameplate --get ip         # one value
nameplate -g serial -g model
nameplate --json           # everything as JSON
nameplate --keys           # every key and its current value
nameplate --live           # include CPU usage and network traffic
nameplate --public-ip      # include the public IP
```

Useful keys: `computer-name`, `model`, `model-id`, `serial`, `uuid`, `chip`, `memory`, `gpu`, `os`, `os-version`, `os-build`, `user`, `uptime`, `boot-time`, `cpu`, `memory-used`, `battery`, `battery-health`, `down`, `up`, `disk`, `disk-free`, `disk-used-percent`, `ip`, `subnet`, `router`, `dns`, `mac`, `ssid`, `interface`, `public-ip`, `date`, `time`, plus per-interface keys like `en0.ip` and `en0.mac`. The same keys work in braces in text lines and the menu bar.

In the **Shortcuts** app, add a **Run Shell Script** action containing `/usr/local/bin/nameplate --get ip` (or any key, or `--json` and then **Get Dictionary from Input**). The output flows into the next action like any other text.

## Making it yours

Everything is in Settings (click the menu bar icon, then the gear).

**Layout.** Every line is in one list. Drag lines to reorder them, untick to hide, and type in the label box to rename one ("Serial" → "S/N"; a single space hides the label). **Add** puts in:

- **Text lines** with your own words and live values in braces: `Owner: Matthew`, `{ip} on {ssid}`, `Up {uptime-short}`. The **{ }** button lists every value.
- **Headings** and **blank lines** to group things.
- **Command output**: any shell command, run as often as you choose (every 5 seconds to every hour). For example `curl -s "wttr.in/?format=3"` for the weather, or `tailscale ip -4`.
- Built-in items you removed, plus live ones: **CPU usage**, **memory in use**, **battery** (level, charging, time left), **battery health** (capacity and cycle count) and **network traffic** (download and upload speed).

The second list sets what each network interface shows, and in what order.

**Appearance.** Font, weight, size, line spacing, text color, separate label and heading colors, opacity, shadow, and usage bars for disk, CPU, memory and battery. Add a **background panel**, either solid or frosted glass, with its own color, rounding and padding.

**Displays.** Show the info on the display with the menu bar, on one particular display, or on every display. **Move on Screen…** lets you drag it anywhere; it stays put relative to the nearest corner. Each display keeps its own position, so a spot that suits a wide monitor doesn't push it off a laptop screen, and the info always stays fully on screen. When it's on one display, dragging it onto another moves it there.

**Looks.** Save the current fonts, colors and background as a named look and switch between looks any time. Built-in looks include Frosted Card, Terminal, Minimal, Big and Bold, and one for light wallpapers.

**Menu bar.** Show the icon, the text, or both. The text can be your IP, the computer name, or your own mix such as `{ip} · {cpu}` or `↓{down} ↑{up}`.

## The Wi-Fi network name

Since macOS Sonoma, apps only get the Wi-Fi network name if they're allowed to use Location Services. Nameplate asks once, the first time it runs. It never reads or stores your location. If you said no, turn Nameplate on in System Settings › Privacy & Security › Location Services; everything else works either way.

## What leaves your Mac

Nothing, unless you turn on **Public IP address** (or use `{public-ip}`). Then Nameplate asks api.ipify.org for your public address when your network changes and every 15 minutes. Commands you add run on your Mac and can do whatever you write in them.

## Update

Run the install command again. It quits the running copy, puts the new one in its place and starts it. Your settings are kept. macOS may ask again about Location Services after an update.

## Build it yourself

You need Apple's free developer tools. Run `xcode-select -p` in Terminal; if it prints an error instead of a path, run `xcode-select --install` first. Then:

```
git clone https://github.com/mmzeller/nameplate.git ~/Nameplate
bash ~/Nameplate/build.sh
```

To update a copy you built, run `bash ~/Nameplate/update.sh`. To compile without installing, use `bash ~/Nameplate/build.sh --no-install`; the app ends up in `~/Nameplate/build`.

GitHub also builds Nameplate on every change (see the Actions tab), starts it to make sure it runs, and leaves the results on the `build-status` branch. When the version number in `Sources/NameplateCore/Models.swift` goes up and those checks pass, the build is published as a new release, and the install command picks it up.

## Uninstall

Quit Nameplate (right-click the menu bar icon › Quit), then run:

```
rm -rf /Applications/Nameplate.app
sudo rm -f /usr/local/bin/nameplate
defaults delete com.mmzeller.Nameplate
```

Turn off **Launch at login** first if you'd switched it on, or remove Nameplate from System Settings › General › Login Items.

## How it's put together

- `Sources/NameplateCore` reads the system: `sysctl` and the I/O Registry for hardware, the System Configuration dynamic store (what `scutil` reads) for the network, CoreWLAN for Wi-Fi, and the file system for disks. Both the app and the command-line tool use it.
- `Sources/NameplateCore/Layout.swift` is the list of lines you arrange in Settings; `LiveSampler.swift` measures CPU, memory, battery and traffic; `CommandRunner.swift` runs your commands.
- `Sources/Nameplate` is the app: desktop windows, the menu bar panel, Settings, looks, keyboard shortcuts, and the change watcher.
- `Sources/NameplateCLI` is the `nameplate` command.
