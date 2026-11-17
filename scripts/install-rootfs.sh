#!/system/bin/sh
set -eu
MODE="${1:-}"
SOURCE="${2:-}"
case "$MODE" in --check|--install) ;; *) echo 'Use install-phone.sh from ordinary Termux.' >&2; exit 2;; esac
case "$SOURCE" in /*) ;; *) echo 'An absolute repository path is required.' >&2; exit 2;; esac
case "$SOURCE" in *[!a-zA-Z0-9_./-]*) echo 'Unsupported repository path.' >&2; exit 2;; esac
test "$(id -u)" = 0 || { echo 'Root access is required.' >&2; exit 1; }
BASE=/data/local/dsh-verify-20261117-a1
ROOTFS="$BASE/rootfs"
if [ -e "$BASE" ] || [ -L "$BASE" ]; then
  echo 'Installation directory already exists; nothing was overwritten. Use bash phone.sh status/start/open for an existing installation.' >&2
  exit 17
fi
test "$(getprop ro.product.cpu.abi)" = arm64-v8a || { echo 'This installation requires arm64-v8a.' >&2; exit 1; }
for tool in tar chroot unshare mknod nohup setsid sha256sum; do
  command -v "$tool" >/dev/null || { echo "Missing Android tool: $tool" >&2; exit 1; }
done
/system/bin/unshare -m /system/bin/true || { echo 'A private mount namespace is not available.' >&2; exit 1; }
for file in assets.sh bootstrap-linux.sh enter-chroot.sh install-harness.sh service.sh start-harness.sh open-phone.sh; do
  test -f "$SOURCE/scripts/$file" || { echo "Missing repository file: scripts/$file" >&2; exit 1; }
done
test -f "$SOURCE/tests/native-smoke.cjs"
if [ "$MODE" = --check ]; then
  echo 'Preflight passed: root, ARM64, required Android tools, mount namespace, and fresh target. This does not prove full installation compatibility.'
  exit 0
fi
. "$SOURCE/scripts/assets.sh"
printf '%s  %s\n' "$UBUNTU_SHA256" "$SOURCE/.downloads/$UBUNTU_FILE" | sha256sum -c -
printf '%s  %s\n' "$NODE_SHA256" "$SOURCE/.downloads/$NODE_FILE" | sha256sum -c -
umask 077
# Atomic mkdir also refuses a target that appeared after the initial check.
mkdir "$BASE"
mkdir "$ROOTFS" "$BASE/scripts" "$BASE/logs"
printf '%s\n' dsh-verification-20261117-a1 > "$BASE/.verification-owner"
trap 'result=$?; if [ "$result" -ne 0 ]; then echo "Installation incomplete; files were retained for diagnosis. Do not overwrite the installation directory or rerun blindly." >&2; fi' 0
trap 'exit 129' 1
trap 'exit 130' 2
trap 'exit 143' 15
tar -xzf "$SOURCE/.downloads/$UBUNTU_FILE" -C "$ROOTFS"
mkdir -p "$ROOTFS/usr/local" "$ROOTFS/proc" "$ROOTFS/dev" "$ROOTFS/tmp"
tar -xzf "$SOURCE/.downloads/$NODE_FILE" -C "$ROOTFS/usr/local" --strip-components=1
chmod 1777 "$ROOTFS/tmp"
rm -f "$ROOTFS/etc/resolv.conf"
printf 'nameserver 223.5.5.5\nnameserver 1.1.1.1\n' > "$ROOTFS/etc/resolv.conf"
chmod 644 "$ROOTFS/etc/resolv.conf"
for file in bootstrap-linux.sh enter-chroot.sh install-harness.sh service.sh start-harness.sh open-phone.sh; do
  cp "$SOURCE/scripts/$file" "$BASE/scripts/$file"
  chmod 700 "$BASE/scripts/$file"
done
cp "$BASE/scripts/bootstrap-linux.sh" "$ROOTFS/root/bootstrap-linux.sh"
"$BASE/scripts/enter-chroot.sh" admin /bin/bash /root/bootstrap-linux.sh
cp "$SOURCE/scripts/install-harness.sh" "$ROOTFS/home/dsh/install-harness.sh"
cp "$SOURCE/scripts/start-harness.sh" "$ROOTFS/home/dsh/start-harness.sh"
cp "$SOURCE/tests/native-smoke.cjs" "$ROOTFS/home/dsh/runtime/native-smoke.cjs"
chown 2000:2000 "$ROOTFS/home/dsh/install-harness.sh" "$ROOTFS/home/dsh/start-harness.sh" "$ROOTFS/home/dsh/runtime/native-smoke.cjs"
chmod 700 "$ROOTFS/home/dsh/install-harness.sh" "$ROOTFS/home/dsh/start-harness.sh"
"$BASE/scripts/enter-chroot.sh" user /bin/bash /home/dsh/install-harness.sh
"$BASE/scripts/enter-chroot.sh" user /usr/local/bin/node /home/dsh/runtime/native-smoke.cjs
"$BASE/scripts/service.sh" start
trap - 0 1 2 15
