#!/system/bin/sh
set -eu
BASE=/data/local/dsh-verify-20261117-a1
PIDFILE="$BASE/service.pid"
alive() {
  [ -r "$PIDFILE" ] || return 1
  PID=$(cat "$PIDFILE")
  case "$PID" in ''|*[!0-9]*) return 1;; esac
  [ "$(readlink "/proc/$PID/root" 2>/dev/null)" = "$BASE/rootfs" ] || return 1
  kill -0 "$PID" 2>/dev/null
}
case "${1:-status}" in
  start)
    if alive; then
      printf 'Already running: %s\n' "$PID"
      exit 0
    fi
    nohup setsid "$BASE/scripts/enter-chroot.sh" user /bin/bash /home/dsh/start-harness.sh > "$BASE/logs/web.log" 2>&1 < /dev/null &
    PID=$!
    printf '%s\n' "$PID" > "$PIDFILE"
    printf 'Started: %s\n' "$PID"
    for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
      if alive && grep -q '^dsh web: http://127.0.0.1:3080/' "$BASE/logs/web.log"; then
        printf 'Ready: http://127.0.0.1:3080/ (use the authenticated launch URL)\n'
        exit 0
      fi
      sleep 1
    done
    printf 'Startup did not become ready; inspect logs/web.log\n' >&2
    exit 1
    ;;
  stop)
    if alive; then
      kill -TERM "$PID"
      printf 'Sent graceful stop: %s\n' "$PID"
    else
      printf 'Not running\n'
    fi
    ;;
  status)
    if alive; then
      printf 'Running: %s\n' "$PID"
      grep -E '^(Uid|Gid|CapEff|CapBnd|NoNewPrivs):' "/proc/$PID/status"
    else
      printf 'Not running\n'
      exit 1
    fi
    ;;
  *) printf 'Usage: service.sh start|stop|status\n' >&2; exit 2;;
esac
