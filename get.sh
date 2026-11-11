#!/usr/bin/env bash
# One-step installer for Laughdots.
#   bash <(curl -fsSL https://raw.githubusercontent.com/hassankhan2608/laughdots/main/get.sh)
# Optional overrides: LAUGHDOTS_REPO, LAUGHDOTS_DIR
set -e

REPO="${LAUGHDOTS_REPO:-https://github.com/hassankhan2608/laughdots.git}"
DIR="${LAUGHDOTS_DIR:-$HOME/repos/laughdots}"

if [ -d "$DIR/.git" ]; then
    echo "[laughdots] updating $DIR"
    git -C "$DIR" pull --ff-only
else
    echo "[laughdots] cloning into $DIR"
    git clone "$REPO" "$DIR"
fi

cd "$DIR"
if [ "$#" -eq 0 ]; then
    set -- install
fi
exec ./setup "$@"
