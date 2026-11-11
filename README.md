# Laughdots

Personal Hyprland dotfiles: a fork of [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland)
with the Quickshell shell replaced by [end4-pC](https://github.com/pctrade/end4-pC).

The full upstream documentation (screenshots, features, wiki links) is in
[.github/README.md](.github/README.md). This file describes what is different here
and how to install it.

## What this is

| Layer | Source |
|---|---|
| Hyprland config, installers, app configs | end-4/dots-hyprland, unmodified apart from the changes below |
| Quickshell shell | end4-pC, vendored at `dots/.config/quickshell/end4-pC` |
| AUR helper | **paru** (upstream uses yay) |

## Changes from upstream end-4

1. **Shell swapped.** `dots/.config/quickshell/ii` is gone; the shell lives in
   `dots/.config/quickshell/end4-pC`, and `qsConfig` is `end4-pC`.
   This also affects:
   - `sdata/subcmd-install/3.files-exp.yaml` (install mapping)
   - `dots/.config/fish/config.fish` (`alias q 'qs -c end4-pC'`)
   - `dots/.config/hypr/hyprland/variables.lua` (`qsConfig`, settings app)
   - docs, issue templates and the translation tool defaults
2. **Settings app.** end4-pC has no standalone `settings.qml`, so the settings
   keybind now uses `qs -c $qsConfig ipc call settings toggle` (the shell's IPC
   handler) with the same desktop-settings fallbacks.
3. **paru instead of yay.**
   - `sdata/dist-arch/install-deps.sh` installs `paru-bin` if paru is missing,
     and uses `paru -S` for AUR dependencies (`--sudoloop` dropped: paru does
     not have that flag).
   - `sdata/dist-arch/uninstall-deps.sh` removes packages with `paru -Rns`.
   - The vendored shell prefers paru over yay for updates (`Updates.qml`,
     `DotsUpdater.qml`, `UpdatesCount.qml`) and for optional installs
     (`switchwall.sh`, `preset_share_setup.sh`).
4. **No submodules.** Upstream pulls `rounded-polygon-qmljs` as a git submodule
   for `modules/common/widgets/shapes`; here those files are plain files in the
   repo, so `git clone` works without `--recursive`.

## Install

```sh
git clone <this-repo> ~/repos/laughdots
cd ~/repos/laughdots
./setup install
```

The installer is end-4's own interactive setup:

- shows every command before running it
- backs up clashing configs to a timestamped directory
- leaves `~/.config/hypr/custom/` alone if it already exists

Other subcommands:

```sh
./setup uninstall        # remove installed components
./setup exp-update       # update the dots from upstream
./setup --help           # full list
```

After installing, reload the compositor and (re)start the shell:

```sh
hyprctl reload
pkill qs; qs -c end4-pC >/dev/null 2>&1 & disown
```

### Requirements

- Arch-based distro (pacman). The dependency installer is quite Arch-specific
  (`sdata/dist-arch/`); other distros have partial support in `sdata/dist-*`.
- Hyprland 0.55 or newer (Lua-configured dots)
- A working build toolchain (`base-devel`) for the AUR packages

## Layout

```
dots/.config/hypr/                  Hyprland (Lua config, scripts, hyprlock/hypridle)
dots/.config/quickshell/end4-pC/    Quickshell shell (end4-pC)
dots/.config/{kitty,foot,fish,fuzzel,mpv,wlogout,Kvantum,matugen,...}
dots/.local/share/                  icons, konsole profiles
sdata/                              installer backend (per-distro dependency lists)
setup                               installer entry point
```

## Known caveats

- **`DotsUpdater.qml` still points at `pctrade/end4-pC`.** Pressing "update dots"
  inside the shell clones upstream over the vendored copy and would discard the
  changes tracked in this repo. Repoint it at laughdots (or disable it) before
  using that button.
- Features from immaterial-impulse (the setup these dots grew out of) are being
  ported selectively, not wholesale.
- The old imi SDDM theme is not part of this repo.

## Licence

GPL-3.0, inherited from end-4/dots-hyprland (`LICENSE`) and end4-pC
(`dots/.config/quickshell/end4-pC/LICENSE`). Per-file attribution is kept in the
vendored shell.
