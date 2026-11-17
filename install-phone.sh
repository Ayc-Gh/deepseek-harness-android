#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in ''|--check) ;; *) echo 'Usage: bash install-phone.sh [--check]' >&2; exit 2;; esac
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
case "$repo_dir" in *[!a-zA-Z0-9_./-]*) echo 'Clone into a path without spaces or special characters, such as the Termux home directory.' >&2; exit 2;; esac
if (( EUID == 0 )); then
  echo 'Run this entry point in ordinary Termux, not after su. It requests root only for the installation phase.' >&2
  exit 2
fi
for tool in su curl sha256sum; do
  command -v "$tool" >/dev/null || { echo "Missing $tool. Install git/curl/coreutils in Termux and ensure the phone has root." >&2; exit 1; }
done
# Discard Termux's loader variables and command paths before Android/chroot tools.
root_command="exec /system/bin/env -i PATH=/system/bin:/system/xbin:/vendor/bin HOME=/data/local/tmp TMPDIR=/data/local/tmp /system/bin/sh '$repo_dir/scripts/install-rootfs.sh'"
su -c "$root_command --check '$repo_dir'"
if [[ "${1:-}" == --check ]]; then exit 0; fi
. "$repo_dir/scripts/assets.sh"
download_dir="$repo_dir/.downloads"
mkdir -p "$download_dir"
verify_archive() {
  local file="$1" expected="$2"
  printf '%s  %s\n' "$expected" "$file" | sha256sum -c - >/dev/null 2>&1
}
download_archive() {
  local name="$1" url="$2" expected="$3" file="$download_dir/$1"
  if [[ -f "$file" ]] && verify_archive "$file" "$expected"; then
    printf 'Using verified archive: %s\n' "$name"
    return
  fi
  curl --fail --location --proto '=https' --proto-redir '=https' --retry 3 --connect-timeout 30 --output "$file.part" "$url"
  if ! verify_archive "$file.part" "$expected"; then
    printf 'SHA256 verification failed: %s. Installation stopped.\n' "$name" >&2
    exit 1
  fi
  mv -- "$file.part" "$file"
  printf 'SHA256 OK: %s\n' "$name"
}
download_archive "$UBUNTU_FILE" "$UBUNTU_URL" "$UBUNTU_SHA256"
download_archive "$NODE_FILE" "$NODE_URL" "$NODE_SHA256"
su -c "$root_command --install '$repo_dir'"
printf 'Installation finished. Open the phone UI with: bash phone.sh open\n'
