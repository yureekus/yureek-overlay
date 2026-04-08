#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo_root"

pkg_dir="net-im/equibop"

latest_json=$(curl -fsSL "https://api.github.com/repos/Equicord/Equibop/releases/latest")
latest_tag=$(printf '%s' "$latest_json" | grep -m1 '"tag_name"' | cut -d '"' -f4)
latest_ver=${latest_tag#v}

current_ebuild=$(ls "$pkg_dir"/equibop-*.ebuild | sed 's#.*/equibop-##; s#\.ebuild##' | sort -V | tail -n1)

if [[ "$latest_ver" != "$current_ebuild" ]]; then
  cp "$pkg_dir/equibop-${current_ebuild}.ebuild" "$pkg_dir/equibop-${latest_ver}.ebuild"
  rm -f "$pkg_dir/equibop-${current_ebuild}.ebuild"
fi

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

fetch_and_hash() {
  local url=$1
  local out=$2
  curl -fsSL "$url" -o "$workdir/$out"

  local size blake sha512
  size=$(stat -c '%s' "$workdir/$out")
  blake=$(b2sum "$workdir/$out" | awk '{print $1}')
  sha512=$(sha512sum "$workdir/$out" | awk '{print $1}')

  printf 'DIST %s %s BLAKE2B %s SHA512 %s\n' "$out" "$size" "$blake" "$sha512"
}

manifest_tmp="$workdir/Manifest"
{
  fetch_and_hash "https://github.com/Equicord/Equibop/releases/download/v${latest_ver}/node_modules-arm64.tar.gz" "equibop-${latest_ver}-node_modules-arm64.tar.gz"
  fetch_and_hash "https://github.com/Equicord/Equibop/releases/download/v${latest_ver}/node_modules-x64.tar.gz" "equibop-${latest_ver}-node_modules-amd64.tar.gz"
  fetch_and_hash "https://github.com/oven-sh/bun/releases/download/bun-v1.3.0/bun-linux-aarch64.zip" "equibop-${latest_ver}-bun-arm64.zip"
  fetch_and_hash "https://github.com/oven-sh/bun/releases/download/bun-v1.3.0/bun-linux-x64.zip" "equibop-${latest_ver}-bun-amd64.zip"
  fetch_and_hash "https://github.com/Equicord/Equibop/archive/refs/tags/v${latest_ver}.tar.gz" "equibop-${latest_ver}.gh.tar.gz"
  fetch_and_hash "https://github.com/Equicord/Equibop/releases/download/v${latest_ver}/org.equicord.equibop.metainfo.xml" "equibop-${latest_ver}.metainfo.xml"
} | sort > "$manifest_tmp"

mv "$manifest_tmp" "$pkg_dir/Manifest"

if [[ "$latest_ver" == "$current_ebuild" ]]; then
  echo "Already on Equibop ${latest_ver}; Manifest refreshed"
else
  echo "Updated to Equibop ${latest_ver}"
fi
