#!/usr/bin/env bash

set -euo pipefail

mem_kib=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
if [ "$mem_kib" -lt 33554432 ]; then
    if [ ! -f "$HOME/bin/swapon.sh" ]; then
        echo "minimum 32GB fizikai + swap memória szükséges!"
        exit 1
    fi
    bash "$HOME/bin/swapon.sh"
fi

if ! command -v 7z >/dev/null 2>&1; then
    echo "7z nincs telepítve!"
    exit 1
fi

if ! command -v julia >/dev/null 2>&1; then
    echo "julia nincs telepítve!"
    exit 1
fi

rm -rf build
julia build_app.jl
strip build/Chaos/bin/Chaos
version=$(awk -F\" '/^version =/ {print $2}' Project.toml)
zip_name="Chaos-linux-x64-v${version}.zip"
7z a -tzip -mx=9 -mmt=on "build/${zip_name}" build/Chaos
