# AGENTS.md — operating omaspaces

Instructions for an AI agent (or a person) working in a fresh clone of this repo.
omaspaces is a workspace-layout builder and dock for Omarchy (Hyprland). This file
is how to set it up and answer the common requests without guessing.

## Requirements
- Omarchy or a Hyprland Wayland session.
- Commands: `python`, `quickshell`, `jq`, `grim`, `hyprland`, `inotify-tools`,
  `wl-clipboard`. Optional: `chromium` (web builder fallback), a Nerd Font.

## Set it up (fresh clone)
```bash
./install-omarchy      # resolves deps, installs to ~/.local (no root)
```
Then add the keybindings it prints to `~/.config/hypr/bindings.lua` and run
`hyprctl reload`. Add `omaspaces dock` to `~/.config/hypr/autostart.lua` if the
user wants the dock always up.

## Handling common requests
| The user asks… | Do this |
|---|---|
| "set up omaspaces" | `./install-omarchy`, add the printed keybindings, `hyprctl reload`. |
| "open the builder" | `omaspaces build` (native editor: pick a template, split tiles, drop apps, Save & Apply). |
| "start the dock" | `omaspaces dock` (add to autostart to persist). |
| "save this workspace as a preset" | `omaspaces save <name>` (snapshots the live workspace exactly). |
| "apply / list / delete a layout" | `omaspaces apply <name>` · `omaspaces list` · `omaspaces rm <name>`. |
| "pin an app to the dock" | `omaspaces dock pin <id>` (unpin / add likewise). |

## How it works (for debugging)
Layouts are plain JSON in `~/.config/omarchy/layouts/` — an agent can author one
directly. A layout's `region` is `[x, y, w, h]` as fractions of the monitor work
area, so it's resolution-independent; `apply` places windows pixel-perfectly,
matching the monitor size minus the bar and gaps. The editor and dock are Quickshell
QML in `share/qml/` and `share/qml-dock/`; the CLI is `bin/omaspaces`. The editor
shows tile sizes in real pixels and clamps resizing to a usable minimum.

## Pairs with omabeam
[omabeam](https://github.com/qlfahey/omabeam) (the phone bridge) detects omaspaces
and exposes building/applying/deleting layouts from the phone. They ship separately.
