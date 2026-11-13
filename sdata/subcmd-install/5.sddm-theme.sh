#!/usr/bin/env bash
# 5.sddm-theme.sh — OPTIONAL SDDM login theme.
#
# laughdots wrapper around the UPSTREAM ii SDDM theme installer
# (3d3f/ii-sddm-theme). It is OPT-IN: it does nothing unless INSTALL_SDDM=1,
# which `./setup install --sddm` and `./setup install-sddm` set for you.
#
# Why upstream and not the XephyLon/imi-sddm-theme fork: the fork carried fixes
# for a shell rename that only ever existed in immaterial-impulse, and a
# user-owned staging dir that laughdots does not need. Upstream reads
# ~/.config/illogical-impulse/config.json directly, which is exactly where this
# shell keeps its config, so the "ii + Matugen" mode works unchanged.
#
# This stays a thin hand-off, with ONE addition: upstream's setup.sh clones the
# theme's default branch with no ref, so pinning only the installer would let
# the theme content drift. We therefore pre-clone the theme at SDDM_REF into a
# temp mirror and hand that mirror to the fetched installer through a throwaway
# GIT_CONFIG_GLOBAL with an url.<mirror>.insteadOf rewrite. Installer and theme
# content are then the same revision, and nothing global is touched.
#
# Run it standalone:
#   INSTALL_SDDM=1 bash sdata/subcmd-install/5.sddm-theme.sh
#
# Environment overrides:
#   SDDM_REPO_RAW              base raw URL of the theme repo
#   SDDM_REF                   pinned revision (installer + theme content)
#   INSTALL_SDDM_MODE          ii-matugen | matugen-only | no-matugen
#                              (skips upstream's mode menu when set)
#   LAUGHDOTS_ASSUME_YES=1     answer upstream's prompts non-interactively
set -euo pipefail

# ─── colours ───
if [[ -t 1 ]]; then
  C_CYAN=$'\e[36m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'
  C_RED=$'\e[31m'; C_BOLD=$'\e[1m'; C_RST=$'\e[0m'
else
  C_CYAN=; C_GREEN=; C_YELLOW=; C_RED=; C_BOLD=; C_RST=
fi

# ─── configuration ───
readonly THEME_NAME="ii-sddm-theme"
readonly THEME_REPO="https://github.com/3d3f/ii-sddm-theme"
readonly SDDM_REPO_RAW="${SDDM_REPO_RAW:-https://raw.githubusercontent.com/3d3f/ii-sddm-theme}"
# Upstream ships no tags; this is the tip of main (1d4bcb6, 2026-06-02) and the
# newest commit there is. Bump by reading the SHA off 3d3f/ii-sddm-theme's main.
readonly SDDM_REF="${SDDM_REF:-1d4bcb66647f750bcc14d73de025eae8dd1e3db7}"
readonly SETUP_URL="${SDDM_REPO_RAW}/${SDDM_REF}/setup.sh"
readonly STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/laughdots"
readonly STATE_FILE="${STATE_DIR}/sddm-theme-installed"

# Artifacts of the fork laughdots used to install. Removed so the two themes
# cannot both claim the greeter.
readonly LEGACY_THEME_DIR="/usr/share/sddm/themes/imi-sddm-theme"
readonly LEGACY_STAGING_DIR="/var/lib/imi-sddm-theme"
readonly LEGACY_CONF="/etc/sddm.conf.d/zz-imi-sddm-theme.conf"
readonly LEGACY_CONFIG_DIR="${HOME}/.config/imi-sddm-theme"

log_info()  { printf '  %s[INFO]%s %s\n' "$C_CYAN" "$C_RST" "$*"; }
log_ok()    { printf '  %s[OK]%s   %s\n' "$C_GREEN" "$C_RST" "$*"; }
log_warn()  { printf '  %s[WARN]%s %s\n' "$C_YELLOW" "$C_RST" "$*" >&2; }
log_error() { printf '  %s[ERR]%s  %s\n' "$C_RED" "$C_RST" "$*" >&2; }
log_step()  { printf '\n%s-- %s%s\n' "$C_BOLD" "$*" "$C_RST"; }

banner() {
  printf '\n%s' "$C_CYAN"
  cat <<'ASCII'
___                                ___            ___            ___                  
(   )                              (   )          (   )          (   )                 
 | |    .---.   ___  ___    .--.    | | .-.     .-.| |    .--.    | |_         .--.    
 | |   / .-, \ (   )(   )  /    \   | |/   \   /   \ |   /    \  (   __)     /  _  \   
 | |  (__) ; |  | |  | |  ;  ,-. '  |  .-. .  |  .-. |  |  .-. ;  | |       . .' `. ;  
 | |    .'`  |  | |  | |  | |  | |  | |  | |  | |  | |  | |  | |  | | ___   | '   | |  
 | |   / .'| |  | |  | |  | |  | |  | |  | |  | |  | |  | |  | |  | |(   )  _\_`.(___) 
 | |  | /  | |  | |  | |  | |  | |  | |  | |  | |  | |  | |  | |  | | | |  (   ). '.   
 | |  ; |  ; |  | |  ; '  | '  | |  | |  | |  | '  | |  | '  | |  | ' | |   | |  `\ |  
 | |  ' `-'  |  ' `-'  /  '  `-' |  | |  | |  ' `-'  /  '  `-' /  ' `-' ;   ; '._,' '  
 (___) `.__.'_.   '.__.'    `.__. | (___)(___)  `.__,'    `.__.'    `.__.     '.___.'   
                           ( `-' ;                                                     
                            `.__. 
ASCII
  printf '%s\n' "$C_RST"
  printf '  %sSDDM login theme — optional step%s\n' "$C_BOLD" "$C_RST"
  printf '  %sInstalls upstream ii-sddm-theme (pinned %s)%s\n\n' \
    "$C_CYAN" "${SDDM_REF:0:12}" "$C_RST"
}

confirm() {
  local prompt="$1" reply
  if [[ "${LAUGHDOTS_ASSUME_YES:-0}" == "1" ]]; then
    printf '===> %s [y/n]: y (auto)\n' "$prompt"
    return 0
  fi
  read -r -p "===> ${prompt} [y/n]: " reply
  [[ "$reply" == [yY] ]]
}

# ─── gate ───
if [[ "${INSTALL_SDDM:-0}" != "1" ]]; then
  echo "[laughdots] SDDM theme: skipped (use './setup install-sddm' or './setup install --sddm')."
  exit 0
fi

banner

# ─── preflight ───
if [[ $EUID -eq 0 ]]; then
  log_error "Do not run this as root. It will use sudo when it needs to."
  exit 1
fi

if ! command -v pacman >/dev/null 2>&1; then
  log_warn "This theme installer is Arch-only (it installs packages with pacman)."
  log_warn "Skipping the SDDM theme on this system."
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  log_error "curl is required to fetch the theme installer."
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  log_error "git is required to pin the theme content to ${SDDM_REF:0:12}."
  exit 1
fi

if ! command -v sddm >/dev/null 2>&1; then
  log_warn "SDDM is not installed; the theme installer will install and enable it."
fi

if [[ -n "${INSTALL_SDDM_MODE:-}" ]]; then
  case "$INSTALL_SDDM_MODE" in
    ii-matugen|matugen-only|no-matugen) ;;
    *) log_error "INSTALL_SDDM_MODE='${INSTALL_SDDM_MODE}' is not one of ii-matugen, matugen-only, no-matugen."
       exit 1 ;;
  esac
fi

# ─── what it will do ───
cat <<EOF
This step will:
  1. remove the old imi-sddm-theme install, if present
  2. install SDDM + Qt6 greeter packages (pacman)
  3. install the theme's fonts to /usr/share/fonts/ii-sddm-theme-fonts
  4. install the theme to /usr/share/sddm/themes/${THEME_NAME}
  5. write /etc/sddm.conf.d/${THEME_NAME}.conf and enable sddm.service
  6. wire the matugen post-hook and a NOPASSWD rule for the greeter apply script
     (so the login screen follows wallpaper/color changes)
EOF
printf '\n'

if ! confirm "Continue?"; then
  log_warn "SDDM theme installation skipped."
  exit 0
fi

if ! sudo -v; then
  log_error "sudo authentication failed."
  exit 1
fi

# ─── drop the fork's install ───
log_step "Removing the old imi-sddm-theme install"
removed=0
for path in "$LEGACY_THEME_DIR" "$LEGACY_STAGING_DIR"; do
  if [[ -e "$path" ]]; then
    sudo rm -rf "$path" && log_ok "removed $path"
    removed=1
  fi
done
if [[ -e "$LEGACY_CONF" ]]; then
  sudo rm -f "$LEGACY_CONF" && log_ok "removed $LEGACY_CONF"
  removed=1
fi
if [[ -d "$LEGACY_CONFIG_DIR" ]]; then
  rm -rf "$LEGACY_CONFIG_DIR" && log_ok "removed $LEGACY_CONFIG_DIR"
  removed=1
fi
(( removed == 0 )) && log_info "nothing to remove"

# ─── which menu answer/prompt ───
II_CONFIG="$HOME/.config/illogical-impulse/config.json"
MATUGEN_CONF="$HOME/.config/matugen/config.toml"
has_ii=false; has_matugen=false
[[ -f "$II_CONFIG" ]] && has_ii=true
[[ -f "$MATUGEN_CONF" ]] && has_matugen=true

# Upstream's menu is built from the same two detections, so the numbering below
# mirrors it exactly. Only used to answer it non-interactively.
menu_choice=""
if $has_ii && $has_matugen; then
  case "${INSTALL_SDDM_MODE:-ii-matugen}" in
    ii-matugen)    menu_choice=1 ;;
    matugen-only)  menu_choice=2 ;;
    no-matugen)    menu_choice=3 ;;
  esac
elif $has_matugen; then
  case "${INSTALL_SDDM_MODE:-matugen-only}" in
    ii-matugen|matugen-only) menu_choice=1 ;;
    no-matugen)              menu_choice=2 ;;
  esac
else
  menu_choice=1
fi

# ─── fetch the pinned installer ───
log_step "Fetching the theme installer"
log_info "${SETUP_URL}"
TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT
TMP_SETUP="${TMP_DIR}/setup.sh"
if ! curl -fsSL "$SETUP_URL" -o "$TMP_SETUP"; then
  log_error "Could not download the installer from the pinned revision ${SDDM_REF}."
  log_error "Check your network, or override SDDM_REF/SDDM_REPO_RAW."
  exit 1
fi
if ! grep -q '3d3f/ii-sddm-theme' "$TMP_SETUP"; then
  log_error "The downloaded setup.sh does not look like upstream's installer."
  exit 1
fi
chmod +x "$TMP_SETUP"
log_ok "Installer fetched (${SDDM_REF:0:12})"

# ─── pin the theme content ───
log_step "Pinning the theme content"
MIRROR="${TMP_DIR}/mirror"
if ! git clone -q "$THEME_REPO" "$MIRROR"; then
  log_error "Could not clone ${THEME_REPO}."
  exit 1
fi
if ! git -C "$MIRROR" checkout -q "$SDDM_REF"; then
  log_error "Could not check out ${SDDM_REF} in the theme mirror."
  exit 1
fi
GITCFG="${TMP_DIR}/gitconfig"
printf '[url "file://%s"]\n\tinsteadOf = %s\n' "$MIRROR" "$THEME_REPO" > "$GITCFG"
log_ok "Theme content pinned to ${SDDM_REF:0:12}"

# ─── hand off ───
log_step "Running the theme installer"
if [[ -n "${INSTALL_SDDM_MODE:-}" ]]; then
  printf '%s\n' "  Integration mode: ${INSTALL_SDDM_MODE} (menu answered automatically)"
fi
printf '\n'

set +e
if [[ "${LAUGHDOTS_ASSUME_YES:-0}" == "1" ]]; then
  printf 'y\n%s\n' "$menu_choice" | GIT_CONFIG_GLOBAL="$GITCFG" bash "$TMP_SETUP"
else
  GIT_CONFIG_GLOBAL="$GITCFG" bash "$TMP_SETUP"
fi
rc=$?
set -e

if (( rc != 0 )); then
  log_warn "The theme installer exited non-zero (declined or failed)."
  log_warn "Your previous login theme, if any, is untouched."
  exit 1
fi

# ─── verify ───
log_step "Verifying the install"
ok=true
[[ -d "/usr/share/sddm/themes/${THEME_NAME}" ]] || { log_error "theme dir missing"; ok=false; }
[[ -f "${HOME}/.config/${THEME_NAME}/sddm-theme-apply.sh" ]] || { log_error "apply script missing"; ok=false; }
if ! grep -qx "Current=${THEME_NAME}" "/etc/sddm.conf.d/${THEME_NAME}.conf" 2>/dev/null; then
  log_error "/etc/sddm.conf.d/${THEME_NAME}.conf does not select the theme"
  ok=false
fi
$ok || exit 1
log_ok "Theme installed and selected"

mkdir -p "$STATE_DIR"
printf 'theme=%s\nref=%s\ninstalled=%s\n' \
  "$THEME_NAME" "$SDDM_REF" "$(date -Is)" > "$STATE_FILE" 2>/dev/null \
  && log_ok "Recorded install state in ${STATE_FILE}"

printf '\n%s  SDDM theme installed. Log out to see it.%s\n' "$C_GREEN" "$C_RST"
printf '  Test it in this session with:\n'
printf '    sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/%s\n\n' "$THEME_NAME"
