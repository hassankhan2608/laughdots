#!/usr/bin/env bash
# 5.sddm-theme.sh — OPTIONAL SDDM login theme.
#
# laughdots wrapper around the imi SDDM theme installer (XephyLon/imi-sddm-theme,
# itself a fork of 3d3f/ii-sddm-theme). It is OPT-IN: it does nothing unless
# INSTALL_SDDM=1, which `./setup install --sddm` and `./setup install-sddm` set
# for you.
#
# This is deliberately a thin hand-off, like immaterial-impulse's version:
# the theme ships its own setup.sh that installs dependencies, fonts, the theme
# directory, /etc/sddm.conf.d, the greeter staging directory, the Matugen
# template block and enables sddm.service. We only brand the entry point and
# choose the integration mode, then run that installer.
#
# The installer AND the theme content are pinned to the same SHA: fetching
# setup.sh at a ref pins only the installer, so the same ref is passed through
# as IMI_SDDM_THEME_REF. Read that SHA from imi-sddm-theme's *main* after
# merging there, never from a feature branch (that repo rebases; a pin naming a
# rebased-away commit fetches today and 404s once the branch is deleted).
#
# Run it standalone:
#   INSTALL_SDDM=1 bash sdata/subcmd-install/5.sddm-theme.sh
#
# Environment overrides:
#   SDDM_REPO_RAW              base raw URL of the theme repo
#   SDDM_REF                   pinned revision (installer + theme content)
#   INSTALL_SDDM_MODE          ii-matugen | matugen-only | no-matugen
#   LAUGHDOTS_ASSUME_YES=1     skip laughdots' own confirmations (used by -f)
#   SDDM_THEMES_DIR, SDDM_CONF_DIR, STAGING_DIR
#                              passed through to the theme installer
set -euo pipefail

# ─── colours ───
if [[ -t 1 ]]; then
  C_CYAN=$'\e[36m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'
  C_RED=$'\e[31m'; C_BOLD=$'\e[1m'; C_RST=$'\e[0m'
else
  C_CYAN=; C_GREEN=; C_YELLOW=; C_RED=; C_BOLD=; C_RST=
fi

# ─── configuration ───
readonly SDDM_REPO_RAW="${SDDM_REPO_RAW:-https://raw.githubusercontent.com/XephyLon/imi-sddm-theme}"
# v0.3.1 release commit. Keep in sync with the theme's own releases. See header.
readonly SDDM_REF="${SDDM_REF:-1b0ac8bb647cb9089a13746bf904296c170fb74f}"
readonly SETUP_URL="${SDDM_REPO_RAW}/${SDDM_REF}/setup.sh"
readonly STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/laughdots"
readonly STATE_FILE="${STATE_DIR}/sddm-theme-installed"

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
  printf '  %sInstalls imi-sddm-theme (pinned %s)%s\n\n' \
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
  1. install SDDM + Qt6 greeter packages (pacman)
  2. install the theme's fonts to /usr/share/fonts
  3. install the theme to /usr/share/sddm/themes/imi-sddm-theme
  4. write /etc/sddm.conf.d/zz-imi-sddm-theme.conf and enable sddm.service
  5. prepare the greeter staging dir so colors/wallpaper can sync later
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

# ─── integration mode ───
II_CONFIG="$HOME/.config/illogical-impulse/config.json"
MATUGEN_CONF="$HOME/.config/matugen/config.toml"
has_ii=false; has_matugen=false
[[ -f "$II_CONFIG" ]] && has_ii=true
[[ -f "$MATUGEN_CONF" ]] && has_matugen=true

mode="${INSTALL_SDDM_MODE:-}"
if [[ -z "$mode" ]]; then
  log_step "Integration mode"
  if $has_ii && $has_matugen; then
    printf '  1) Shell + Matugen   — greeter follows the shell wallpaper and colors  [default]\n'
    printf '  2) Matugen only      — colors from the wallpaper, settings configured by hand\n'
    printf '  3) Manual            — background and colors configured by hand\n'
    local_choices="1-3"; local_default=1
  elif $has_matugen; then
    printf '  1) Matugen only      — colors from the wallpaper, settings configured by hand  [default]\n'
    printf '  2) Manual            — background and colors configured by hand\n'
    local_choices="1-2"; local_default=1
  else
    printf '  1) Manual            — background and colors configured by hand  [default]\n'
    local_choices="1"; local_default=1
  fi

  if [[ "${LAUGHDOTS_ASSUME_YES:-0}" == "1" ]]; then
    printf '===> mode [%s]: %s (auto)\n' "$local_choices" "$local_default"
    choice="$local_default"
  else
    while true; do
      read -r -p "===> mode [${local_choices}]: " choice
      choice="${choice:-$local_default}"
      [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 )) && (( choice <= ${local_choices#*-} )) && break
      log_error "Enter a number in ${local_choices}."
    done
  fi

  if $has_ii && $has_matugen; then
    case "$choice" in
      1) mode="ii-matugen" ;;
      2) mode="matugen-only" ;;
      *) mode="no-matugen" ;;
    esac
  elif $has_matugen; then
    case "$choice" in
      1) mode="matugen-only" ;;
      *) mode="no-matugen" ;;
    esac
  else
    mode="no-matugen"
  fi
fi

case "$mode" in
  ii-matugen|matugen-only|no-matugen) ;;
  *) log_error "Unknown mode '${mode}' (expected ii-matugen, matugen-only or no-matugen)."; exit 1 ;;
esac
log_ok "Integration mode: ${mode}"

# ─── fetch the pinned installer ───
log_step "Fetching the theme installer"
log_info "${SETUP_URL}"
TMP_SETUP="$(mktemp --suffix=-laughdots-sddm-setup.sh)"
trap 'rm -f "$TMP_SETUP"' EXIT
if ! curl -fsSL "$SETUP_URL" -o "$TMP_SETUP"; then
  log_error "Could not download the installer from the pinned revision ${SDDM_REF}."
  log_error "Check your network, or override SDDM_REF/SDDM_REPO_RAW."
  exit 1
fi
chmod +x "$TMP_SETUP"
log_ok "Installer fetched (${SDDM_REF:0:12})"

# ─── hand off ───
log_step "Running the theme installer"
printf '%s\n' "  Passed through: IMI_SDDM_MODE=${mode}, IMI_SDDM_THEME_REF=${SDDM_REF:0:12}"
printf '\n'

if IMI_SDDM_ASSUME_YES=1 \
   IMI_SDDM_MODE="$mode" \
   IMI_SDDM_THEME_REF="$SDDM_REF" \
     bash "$TMP_SETUP"; then
  mkdir -p "$STATE_DIR"
  if printf 'ref=%s\nmode=%s\ninstalled=%s\n' \
      "$SDDM_REF" "$mode" "$(date -Is)" > "$STATE_FILE" 2>/dev/null; then
    log_ok "Recorded install state in ${STATE_FILE}"
  else
    log_warn "Could not write ${STATE_FILE}; uninstall will have no evidence this was ours."
  fi
  printf '\n%s  SDDM theme installed. Log out to see it.%s\n\n' "$C_GREEN" "$C_RST"
else
  log_warn "The theme installer exited non-zero (declined or failed)."
  log_warn "Your previous login theme, if any, is untouched."
  exit 1
fi
