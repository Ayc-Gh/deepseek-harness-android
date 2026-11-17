#!/usr/bin/env bash
set -euo pipefail
action="${1:-status}"
case "$action" in start|stop|status|open) ;; *) echo 'Usage: bash phone.sh start|stop|status|open' >&2; exit 2;; esac
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
case "$repo_dir" in *[!a-zA-Z0-9_./-]*) echo 'Use a repository path without spaces or special characters.' >&2; exit 2;; esac
if [[ "$action" == open ]]; then
  command_line="/system/bin/sh '$repo_dir/scripts/open-phone.sh'"
else
  command_line="/system/bin/sh '/data/local/dsh-verify-20261117-a1/scripts/service.sh' '$action'"
fi
clean_command="exec /system/bin/env -i PATH=/system/bin:/system/xbin:/vendor/bin HOME=/data/local/tmp TMPDIR=/data/local/tmp $command_line"
if (( EUID == 0 )); then
  exec /system/bin/sh -c "$clean_command"
else
  exec su -c "$clean_command"
fi
