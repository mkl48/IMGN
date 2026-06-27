#!/usr/bin/env bash
# One-shot command-line build for IMGN.
#
#   ./scripts/build.sh           # build everything into build/
#   ./scripts/build.sh model     # just the .rbxm package model
#   ./scripts/build.sh place     # just the dev .rbxl place (src + Showcase)
#   ./scripts/build.sh installer # just the command-bar dist/install.luau
#
# Needs rojo and lune on PATH (see rokit.toml; `rokit install` fetches them).
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p build

build_model() {
	echo "==> model  -> build/IMGN.rbxm"
	rojo build default.project.json -o build/IMGN.rbxm
}

build_place() {
	echo "==> place  -> build/IMGN.rbxl"
	rojo build place.project.json -o build/IMGN.rbxl
}

build_installer() {
	echo "==> installer -> dist/install.luau + dist/bootstrap.luau"
	lune run scripts/build-installer
}

case "${1:-all}" in
	model) build_model ;;
	place) build_place ;;
	installer) build_installer ;;
	all)
		build_model
		build_place
		build_installer
		;;
	*)
		echo "unknown target '$1' (expected: all | model | place | installer)" >&2
		exit 1
		;;
esac

echo "done."
