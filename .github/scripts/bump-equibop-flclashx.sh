#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo_root"

equibop_pkg_dir="net-im/equibop"
flclashx_pkg_dir="net-proxy/flclashx"
flutter_sdk_version="3.41.6"

get_latest_release_tag() {
  local owner_repo=$1
  local latest_json latest_tag

  latest_json=$(curl -fsSL "https://api.github.com/repos/${owner_repo}/releases/latest")
  if command -v jq >/dev/null 2>&1; then
    latest_tag=$(jq -r '.tag_name' <<<"$latest_json")
  else
    latest_tag=$(grep -m1 '"tag_name"' <<<"$latest_json" | cut -d '"' -f4)
  fi

  printf '%s\n' "$latest_tag"
}

get_tree_entry_sha() {
  local owner_repo=$1
  local tag=$2
  local path=$3
  local tree_json

  tree_json=$(curl -fsSL "https://api.github.com/repos/${owner_repo}/git/trees/${tag}?recursive=1")

  if command -v jq >/dev/null 2>&1; then
    jq -r --arg path "$path" '.tree[] | select(.path == $path) | .sha' <<<"$tree_json"
  else
    awk -v path="$path" '
      index($0, "\"path\": \"" path "\"") { in_block=1; next }
      in_block && $0 ~ /"sha":/ {
        gsub(/[",]/, "", $2)
        print $2
        exit
      }
    ' <<<"$tree_json"
  fi
}

current_ebuild_version() {
  local pkg_dir=$1
  local pn=$2
  ls "${pkg_dir}/${pn}-"*.ebuild | sed "s#.*/${pn}-##; s#\.ebuild##" | sort -V | tail -n1
}

replace_or_create_ebuild() {
  local pkg_dir=$1
  local pn=$2
  local from_ver=$3
  local to_ver=$4

  if [[ "$from_ver" != "$to_ver" ]]; then
    cp "${pkg_dir}/${pn}-${from_ver}.ebuild" "${pkg_dir}/${pn}-${to_ver}.ebuild"
    rm -f "${pkg_dir}/${pn}-${from_ver}.ebuild"
  fi
}

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

update_equibop() {
  local latest_tag latest_ver current_ver manifest_tmp

  latest_tag=$(get_latest_release_tag "Equicord/Equibop")
  latest_ver=${latest_tag#v}

  current_ver=$(current_ebuild_version "$equibop_pkg_dir" equibop)
  replace_or_create_ebuild "$equibop_pkg_dir" equibop "$current_ver" "$latest_ver"

  manifest_tmp="$workdir/Manifest.equibop"
  {
    fetch_and_hash "https://github.com/Equicord/Equibop/releases/download/v${latest_ver}/node_modules-arm64.tar.gz" "equibop-${latest_ver}-node_modules-arm64.tar.gz"
    fetch_and_hash "https://github.com/Equicord/Equibop/releases/download/v${latest_ver}/node_modules-x64.tar.gz" "equibop-${latest_ver}-node_modules-amd64.tar.gz"
    fetch_and_hash "https://github.com/oven-sh/bun/releases/download/bun-v1.3.0/bun-linux-aarch64.zip" "equibop-${latest_ver}-bun-arm64.zip"
    fetch_and_hash "https://github.com/oven-sh/bun/releases/download/bun-v1.3.0/bun-linux-x64.zip" "equibop-${latest_ver}-bun-amd64.zip"
    fetch_and_hash "https://github.com/Equicord/Equibop/archive/refs/tags/v${latest_ver}.tar.gz" "equibop-${latest_ver}.gh.tar.gz"
    fetch_and_hash "https://github.com/Equicord/Equibop/releases/download/v${latest_ver}/org.equicord.equibop.metainfo.xml" "equibop-${latest_ver}.metainfo.xml"
  } | sort > "$manifest_tmp"

  mv "$manifest_tmp" "$equibop_pkg_dir/Manifest"

  if [[ "$latest_ver" == "$current_ver" ]]; then
    echo "Equibop already on ${latest_ver}; Manifest refreshed"
  else
    echo "Updated Equibop to ${latest_ver}"
  fi
}

update_flclashx() {
  local latest_tag latest_ver current_ver xhomo_commit manifest_tmp ebuild_path

  latest_tag=$(get_latest_release_tag "pluralplay/FlClashX")
  latest_ver=${latest_tag#v}

  current_ver=$(current_ebuild_version "$flclashx_pkg_dir" flclashx)
  replace_or_create_ebuild "$flclashx_pkg_dir" flclashx "$current_ver" "$latest_ver"

  xhomo_commit=$(get_tree_entry_sha "pluralplay/FlClashX" "${latest_tag}" "core/Clash.Meta")
  if [[ -z "$xhomo_commit" ]]; then
    echo "Failed to resolve xHomo submodule commit for FlClashX ${latest_tag}" >&2
    exit 1
  fi

  ebuild_path="${flclashx_pkg_dir}/flclashx-${latest_ver}.ebuild"
  sed -i -E "s/^XHOMO_COMMIT=\"[0-9a-f]+\"/XHOMO_COMMIT=\"${xhomo_commit}\"/" "$ebuild_path"

  manifest_tmp="$workdir/Manifest.flclashx"
  {
    fetch_and_hash "https://github.com/pluralplay/FlClashX/archive/refs/tags/v${latest_ver}.tar.gz" "flclashx-${latest_ver}.gh.tar.gz"
    fetch_and_hash "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${flutter_sdk_version}-stable.tar.xz" "flclashx-${latest_ver}-flutter-amd64.tar.xz"
    fetch_and_hash "https://github.com/pluralplay/xHomo/archive/${xhomo_commit}.tar.gz" "flclashx-${latest_ver}-xhomo-${xhomo_commit}.tar.gz"
  } | sort > "$manifest_tmp"

  mv "$manifest_tmp" "$flclashx_pkg_dir/Manifest"

  if [[ "$latest_ver" == "$current_ver" ]]; then
    echo "FlClashX already on ${latest_ver}; Manifest refreshed"
  else
    echo "Updated FlClashX to ${latest_ver}"
  fi
}

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

update_equibop
update_flclashx
