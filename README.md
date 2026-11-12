# Laughdots

Official repo: **https://github.com/hassankhan2608/laughdots**

Personal Hyprland dotfiles: a fork of [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland)
with the Quickshell shell replaced by a renamed copy of
[end4-pC](https://github.com/pctrade/end4-pC) that lives here as `laugh`.

Everything needed to install is in this repo — no submodules, no symlinks, no
runtime clones from other repositories.

The full upstream documentation (screenshots, features, wiki links) is in
[.github/README.md](.github/README.md). This file describes what is different here
and how to install it.

## What this is

| Layer | Source |
|---|---|
| Hyprland config, installers, app configs | end-4/dots-hyprland, unmodified apart from the changes below |
| Quickshell shell | `laugh` (vendored from end4-pC) at `dots/.config/quickshell/laugh` |
| AUR helper | **paru** (upstream uses yay) |

## Changes from upstream end-4

1. **Shell swapped.** `dots/.config/quickshell/ii` is gone; the shell lives in
   `dots/.config/quickshell/laugh`, and `qsConfig` is `laugh`.
   This also affects:
   - `sdata/subcmd-install/3.files-exp.yaml` (install mapping)
   - `dots/.config/fish/config.fish` (`alias q 'qs -c laugh'`)
   - `dots/.config/hypr/hyprland/variables.lua` (`qsConfig`, settings app)
   - docs, issue templates and the translation tool defaults
2. **Settings app.** The shell has no standalone `settings.qml`, so the settings
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
5. **No runtime pulls.** The shell's "Update Dots" button (which cloned
   upstream's shell repo over the installed shell) is removed. Nothing in this repo
   fetches code from another repository at runtime or at install time; updates
   happen only when you `git pull` this repo yourself.
6. **No symlinks.** The two icon symlinks inherited from the upstream shell
   (`ai-openai-symbolic.svg`, `google-gemini-symbolic.svg`) are stored as real
   files. The repo contains zero symlinks, and the installer copies files rather
   than linking them.
7. **Upstream CI removed.** `.github/workflows` and `FUNDING.yml` targeted
   end-4's repository and issue tracker; they are not part of this fork.

## Install

```sh
git clone https://github.com/hassankhan2608/laughdots.git ~/repos/laughdots
cd ~/repos/laughdots
./setup install
```

Or in one step:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/hassankhan2608/laughdots/main/get.sh)
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
pkill qs; qs -c laugh >/dev/null 2>&1 & disown
```

### Requirements

- Arch-based distro (pacman). The dependency installer is quite Arch-specific
  (`sdata/dist-arch/`); other distros have partial support in `sdata/dist-*`.
- Hyprland 0.55 or newer (Lua-configured dots)
- A working build toolchain (`base-devel`) for the AUR packages

## Layout

```
dots/.config/hypr/                  Hyprland (Lua config, scripts, hyprlock/hypridle)
dots/.config/quickshell/laugh/    Quickshell shell (laugh, vendored from end4-pC)
dots/.config/{kitty,foot,fish,fuzzel,mpv,wlogout,Kvantum,matugen,...}
dots/.local/share/                  icons, konsole profiles
sdata/                              installer backend (per-distro dependency lists)
setup                               installer entry point
```

## Updates

There is no in-shell updater any more. To update:

```sh
cd ~/repos/laughdots
git pull
./setup install-files     # re-copy configs (backs up clashing files)
hyprctl reload
```

`./setup install` also re-runs dependency installation.

## Known caveats

- Features from immaterial-impulse (the setup these dots grew out of) are being
  ported selectively, not wholesale.
- The old imi SDDM theme is not part of this repo.
- The online preset gallery (`Config.options.profile.onlinePresets`) is off by
  default and only fetches when you explicitly enable and browse it.

## Licence

GPL-3.0, inherited from end-4/dots-hyprland (`LICENSE`) and the vendored shell
(`dots/.config/quickshell/laugh/LICENSE`). Per-file attribution is kept in the
vendored shell.
