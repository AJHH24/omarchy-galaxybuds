<h1 align="center">Galaxy Buds for Omarchy</h1>

<p align="center">
  Your Samsung Galaxy Buds in the <a href="https://omarchy.org">Omarchy</a> bar: battery for each bud and the case, in-ear state, listening mode, ambient level and quick actions.
</p>

<p align="center">
  <a href="README.es.md">Español</a> ·
  <a href="#install">Install</a> ·
  <a href="#compatibility">Compatibility</a> ·
  <a href="#troubleshooting">Troubleshooting</a>
</p>

<p align="center">
  <img src="docs/panel-ambient.png" alt="Panel in Ambient sound mode with the ambient level slider" width="360">
  &nbsp;
  <img src="docs/panel-anc.png" alt="Panel in noise cancelling mode with the right bud charging" width="360">
</p>

## Features

- **Battery** for the left bud, the right bud and the case, with an in-ear / in-case / charging hint. Turns red at 20%.
- **Listening mode**: Off, Ambient sound or Noise cancelling, with the active one checked. Right-click the bar icon to cycle.
- **Ambient level** slider (1 to 5 on the Buds4 Pro), shown while Ambient sound is on.
- **Quick actions**: conversation detection, touch lock, and *Find my earbuds*.
- **Keyboard driven**, like the stock panels: `O` `A` `N` pick a mode, arrows move and adjust, `C` `L` `F` run the actions, `Tab` moves to the neighbouring panel.
- **No polling**. A small bridge pushes changes to a state file the panel watches, so an idle desktop runs nothing on its behalf.

> The panel's interface is in Spanish.

## How it works

```
Galaxy Buds ──Bluetooth──► GalaxyBudsClient ──D-Bus──► galaxybuds-bridge ──► ~/.local/state/galaxybuds/status.json ──► panel
                                  ▲                                                                                       │
                                  └──────────────────────────── D-Bus calls when you click ◄──────────────────────────────┘
```

[GalaxyBudsClient](https://github.com/timschneeb/GalaxyBudsClient) does the hard part: it speaks Samsung's protocol to the earbuds and publishes their state on D-Bus. `bin/galaxybuds-bridge` mirrors that state into one JSON file, and the panel reads it.

## Install

Requirements: Omarchy, your Galaxy Buds paired over Bluetooth, and an x86_64 machine for the patched GalaxyBudsClient (see below).

```bash
omarchy plugin add https://github.com/AJHH24/omarchy-galaxybuds
~/.config/omarchy/plugins/ajhh.galaxybuds/setup
```

`omarchy plugin add` only clones the plugin. `setup` does the rest:

1. Installs `galaxybudsclient-bin` from the AUR. This asks for your sudo password.
2. Downloads the patched GalaxyBudsClient from this repo's [release](https://github.com/AJHH24/omarchy-galaxybuds/releases/tag/gbc-ipc-1), checks it against the SHA256 pinned in `setup` and installs it in `~/.local/opt/galaxybudsclient-ipc`.
3. Installs and starts two user services: `galaxybudsclient` (minimized to the tray) and `galaxybuds-bridge`.
4. Enables the widget in the bar.

Then open **GalaxyBudsClient** once from the launcher (`Super + Space`) and pick your Buds in its setup wizard. That's it.

Run `setup` again any time; it is safe to repeat.

## Usage

| Action | Result |
|---|---|
| Left click on the icon | Open the panel |
| Right click on the icon | Next listening mode |
| `O` / `A` / `N` | Off / Ambient sound / Noise cancelling |
| `←` `→` on the slider | Ambient level down / up |
| `C` / `L` / `F` | Conversation detection / Touch lock / Find my earbuds |
| `R` | Refresh |

From scripts or Hyprland bindings:

```bash
omarchy-shell galaxybuds toggle          # open or close the panel
omarchy-shell galaxybuds cycle           # next listening mode
omarchy-shell galaxybuds off|ambient|anc # pick a mode
omarchy-shell galaxybuds ambientLevel 3  # 1..5
omarchy-shell galaxybuds mode            # prints the current mode
omarchy-shell galaxybuds battery         # prints the battery line
```

Set `hideWhenDisconnected` to `true` in the widget's entry in `~/.config/omarchy/shell.json` to hide the icon while no Buds are connected.

## Compatibility

The panel only draws what GalaxyBudsClient reports for each model.

| Model | Battery and in-ear | Listening mode | Ambient level |
|---|:---:|:---:|:---:|
| Galaxy Buds4 Pro | ✅ | ✅ | ✅ 5 steps |
| Galaxy Buds Pro | ✅ | ✅ | ✅ 4 steps |
| Galaxy Buds2, Buds3, Buds4 | ✅ | ✅ | ✅ 3 steps |
| Galaxy Buds2 Pro, Buds3 Pro, Buds3 FE, Buds FE, Buds Core | ✅ | ✅ | — |
| Galaxy Buds+, Galaxy Buds (2019), Buds Live | ✅ | toggles only | — |

Only the **Buds4 Pro** has been tested on real hardware. The rest follows the same code path.

## The patched GalaxyBudsClient

Stock GalaxyBudsClient 5.2.1 works, but with it the panel can't show or pick the listening mode and ambient level, and on Linux it can lose the earbuds after they go back in the case. I sent the fixes upstream:

| PR | What it fixes |
|---|---|
| [#751](https://github.com/timschneeb/GalaxyBudsClient/pull/751) | NUL characters in D-Bus strings made the bus drop the app after a reconnect |
| [#752](https://github.com/timschneeb/GalaxyBudsClient/pull/752) | BlueZ watchers never unsubscribed, which broke auto-reconnect |
| [#753](https://github.com/timschneeb/GalaxyBudsClient/pull/753) | Exposes the noise control mode and ambient level over D-Bus |

Until they ship in a release, `setup` installs a build of upstream `master` with those three PRs applied. GalaxyBudsClient is GPLv3, and the exact source for that build is commit [`16732a91`](https://github.com/AJHH24/GalaxyBudsClient/commit/16732a91cbfe32c7f70f6662f0f1d4d3617589f8) in my fork. To build it yourself:

```bash
git clone https://github.com/AJHH24/GalaxyBudsClient && cd GalaxyBudsClient
git checkout --detach 16732a91cbfe32c7f70f6662f0f1d4d3617589f8
# Needs the .NET SDK version pinned in global.json: https://learn.microsoft.com/dotnet/core/install/linux
dotnet publish GalaxyBudsClient/GalaxyBudsClient.csproj -c Release -r linux-x64 \
  --self-contained -p:PublishSingleFile=true -o ~/.local/opt/galaxybudsclient-ipc
systemctl --user restart galaxybudsclient
```

Once the PRs are released, you can go back to the AUR package:

```bash
rm ~/.config/systemd/user/galaxybudsclient.service.d/ipc-noise-control.conf
rm ~/.local/share/applications/galaxybudsclient.desktop
systemctl --user daemon-reload && systemctl --user restart galaxybudsclient
```

## Troubleshooting

**The Buds play audio but the panel says they're not connected.** GalaxyBudsClient gives up for good if the Buds were off when it started. The bridge works around this: when BlueZ connects the Buds and the app still hasn't picked them up after 4 seconds, it asks the app to connect. You can also do it by hand:

```bash
gdbus call --session --dest me.timschneeberger.GalaxyBudsClient \
  --object-path /me/timschneeberger/galaxybudsclient \
  --method me.timschneeberger.GalaxyBudsClient.Application.ExecuteAction Connect
```

**"GalaxyBudsClient is not open".** Check the service with `systemctl --user status galaxybudsclient`.

**Only one device at a time.** The Buds connect to one device at a time. While they're on your phone or another computer, this panel shows them as disconnected.

**The widget stopped loading after editing it.** Run `omarchy restart shell`. Hot reload can keep the old QML after an error.

## Uninstall

```bash
systemctl --user disable --now galaxybuds-bridge galaxybudsclient
rm ~/.config/systemd/user/galaxybuds-bridge.service ~/.config/systemd/user/galaxybudsclient.service
rm -r ~/.config/systemd/user/galaxybudsclient.service.d ~/.local/opt/galaxybudsclient-ipc
rm ~/.local/share/applications/galaxybudsclient.desktop
omarchy plugin remove ajhh.galaxybuds
```

## Credits

- [GalaxyBudsClient](https://github.com/timschneeb/GalaxyBudsClient) by Tim Schneeberger, which talks to the earbuds.
- The panel follows the design of [omarchy-pods](https://github.com/thisisgm/omarchy-pods), the AirPods plugin for Omarchy.

Not affiliated with Samsung. Galaxy Buds is a trademark of Samsung Electronics.

## License

[MIT](LICENSE)
