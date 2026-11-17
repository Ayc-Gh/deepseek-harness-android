#!/system/bin/sh
set -eu
BASE=/data/local/dsh-verify-20261117-a1
ROOTFS="$BASE/rootfs"
if [ "${1:-}" != --private ]; then
  exec /system/bin/unshare -m /system/bin/sh "$0" --private "$@"
fi
shift
MODE="${1:-user}"
shift
test "$(cat "$BASE/.verification-owner")" = dsh-verification-20261117-a1
mount_linux() {
  "$ROOTFS/lib/ld-linux-aarch64.so.1" --library-path "$ROOTFS/usr/lib/aarch64-linux-gnu" "$ROOTFS/usr/bin/mount" "$@"
}
mount_linux --make-rprivate /
if grep -Eq ' shared:[0-9]+' /proc/self/mountinfo; then
  printf 'Mount namespace is not recursively private; aborting.\n' >&2
  exit 18
fi
mount_linux -t proc -o nosuid,nodev,noexec proc "$ROOTFS/proc"
mount_linux -t tmpfs -o mode=755,nosuid tmpfs "$ROOTFS/dev"
mkdir -p "$ROOTFS/dev/pts" "$ROOTFS/dev/shm"
chmod 1777 "$ROOTFS/dev/shm"
mknod -m 666 "$ROOTFS/dev/null" c 1 3
mknod -m 666 "$ROOTFS/dev/zero" c 1 5
mknod -m 666 "$ROOTFS/dev/random" c 1 8
mknod -m 666 "$ROOTFS/dev/urandom" c 1 9
mknod -m 666 "$ROOTFS/dev/tty" c 5 0
mount_linux -t devpts -o newinstance,ptmxmode=0666,mode=0620,gid=5 devpts "$ROOTFS/dev/pts"
ln -s pts/ptmx "$ROOTFS/dev/ptmx"
ln -s /proc/self/fd "$ROOTFS/dev/fd"
ln -s /proc/self/fd/0 "$ROOTFS/dev/stdin"
ln -s /proc/self/fd/1 "$ROOTFS/dev/stdout"
ln -s /proc/self/fd/2 "$ROOTFS/dev/stderr"
cd "$ROOTFS"
if [ "$MODE" = admin ]; then
  exec chroot "$ROOTFS" /usr/bin/env -i HOME=/root PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin LANG=C.UTF-8 TERM=xterm-256color "$@"
fi
test "$MODE" = user
exec chroot "$ROOTFS" /usr/bin/env -i HOME=/home/dsh USER=dsh LOGNAME=dsh SHELL=/bin/bash PATH=/usr/local/bin:/usr/bin:/bin LANG=C.UTF-8 TERM=xterm-256color DSH_HOME=/home/dsh/.dsh /usr/bin/setpriv --reuid=2000 --regid=2000 --groups=3003 --inh-caps=-all --ambient-caps=-all --bounding-set=-all --no-new-privs "$@"
