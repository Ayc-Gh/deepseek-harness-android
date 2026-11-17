"""Exercise install.sh with isolated, simulated Termux tools; no root/network installs.

Run as a non-root Linux user: python3 tests/test_bootstrap.py
This verifies orchestration and failure boundaries, not a real Termux installation.
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "install.sh"
URL = "https://github.com/Ayc-Gh/deepseek-harness-android.git"


@unittest.skipUnless(os.name == "posix" and os.geteuid() != 0, "requires non-root Linux")
class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dsh-bootstrap-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.prefix = self.root / "usr"
        self.bin = self.prefix / "bin"
        self.stubs = self.root / "stubs"
        for directory in (self.home, self.bin, self.prefix / "tmp", self.stubs):
            directory.mkdir(parents=True, exist_ok=True)
        # Deliberately exclude git, curl and sha256sum from the starting PATH.
        for name in ("bash", "mkdir", "mktemp", "mv", "rmdir", "cp", "chmod"):
            (self.bin / name).symlink_to(shutil.which(name))
        self.trace = self.root / "trace"
        self.env = {
            "PATH": str(self.bin), "HOME": str(self.home), "PREFIX": str(self.prefix),
            "LC_ALL": "C.UTF-8", "TEST_TRACE": str(self.trace),
            "TEST_STUBS": str(self.stubs), "TEST_BOOTSTRAP": str(SCRIPT),
            "TEST_SHA256SUM": shutil.which("sha256sum"),
        }
        self.write(self.bin / "getprop", 'printf "%s\\n" "${TEST_ARCH:-arm64-v8a}"\n')
        self.write(self.bin / "su", 'echo su >> "$TEST_TRACE"\n[[ "${TEST_ROOT_DENIED:-0}" == 0 ]] || exit 1\nprintf "0\\n"\n')
        self.write(self.stubs / "curl", r'''
echo curl-download >> "$TEST_TRACE"
out=''
while (( $# )); do
  case "$1" in -o|--output) out="$2"; shift 2;; *) shift;; esac
done
[[ -n "$out" ]] || exit 22
if [[ "${TEST_CURL_FAIL:-0}" == 1 ]]; then
  printf 'echo partial-script-executed >> "$TEST_TRACE"\n' > "$out"
  exit 22
fi
cp "$TEST_BOOTSTRAP" "$out"
''')
        self.write(self.bin / "apt-get", r'''
echo "apt-get $*" >> "$TEST_TRACE"
if [[ "${TEST_APT_FAIL:-0}" == 1 ]]; then exit 42; fi
if [[ "$1" == install ]]; then cp "$TEST_STUBS/curl" "$PREFIX/bin/curl"; fi
''')
        self.write(self.bin / "pkg", r'''
echo "pkg $*" >> "$TEST_TRACE"
if [[ "${TEST_PKG_FAIL:-}" == "$1" ]]; then exit 43; fi
if [[ "$1" == install ]]; then
  cp "$TEST_STUBS/git" "$PREFIX/bin/git"
  cp "$TEST_STUBS/curl" "$PREFIX/bin/curl"
  cp "$TEST_SHA256SUM" "$PREFIX/bin/sha256sum"
fi
''')
        self.write(self.stubs / "install-phone.sh", 'echo install-called >> "$TEST_TRACE"\nexit "${TEST_INSTALL_EXIT:-0}"\n')
        self.write(self.stubs / "phone.sh", 'echo "phone $*" >> "$TEST_TRACE"\nexit "${TEST_OPEN_EXIT:-0}"\n')
        self.write(self.stubs / "git", r'''
echo "git $*" >> "$TEST_TRACE"
if [[ "$1" == clone ]]; then
  dest="${@: -1}"
  mkdir -p "$dest/.git"
  cp "$TEST_STUBS/install-phone.sh" "$dest/install-phone.sh"
  cp "$TEST_STUBS/phone.sh" "$dest/phone.sh"
  [[ "${TEST_CLONE_FAIL:-0}" == 0 ]] || exit 128
  exit 0
fi
[[ "$1" == -C ]] || exit 99
shift 2
case "$1" in
  remote) printf '%s\n' "${TEST_ORIGIN:-https://github.com/Ayc-Gh/deepseek-harness-android.git}";;
  status) printf '%s' "${TEST_DIRTY:-}";;
  symbolic-ref) printf '%s\n' "${TEST_BRANCH:-main}";;
  fetch) :;;
  merge-base) [[ "${TEST_LOCAL_COMMITS:-0}" == 0 ]];;
  merge) :;;
  *) exit 99;;
esac
''')

    def write(self, path, body):
        path.write_text("#!/bin/bash\nset -eu\n" + body, encoding="utf-8")
        path.chmod(0o755)

    def run_script(self, *args, starter=False, **environment):
        env = dict(self.env, **environment)
        command = ["/bin/bash", str(SCRIPT), *args]
        if starter:
            guide = (REPO / "docs/PHONE_ONLY.md").read_text(encoding="utf-8")
            block = re.search(r"<!-- one-click-command -->\s*```bash\n(.*?)\n```", guide, re.S)
            self.assertIsNotNone(block, "documented one-click command must exist")
            command = ["/bin/bash", "-c", block.group(1)]
        return subprocess.run(command, env=env, text=True, capture_output=True, timeout=15)

    def events(self):
        return self.trace.read_text() if self.trace.exists() else ""

    def seed_repo(self):
        repo = self.home / "deepseek-harness-android"
        (repo / ".git").mkdir(parents=True)
        for name in ("install-phone.sh", "phone.sh"):
            shutil.copy(self.stubs / name, repo / name)
        return repo

    def assert_stopped_before_install(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("install-called", self.events())
        self.assertNotIn("phone open", self.events())

    def test_fresh_environment_without_git_or_curl(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        events = self.events()
        self.assertLess(events.index("apt-get install"), events.index("pkg update"))
        self.assertLess(events.index("pkg install"), events.index("git clone"))
        self.assertLess(events.index("install-called"), events.index("phone open"))
        self.assertTrue((self.home / "deepseek-harness-android/install-phone.sh").exists())

    def test_documented_one_click_command_without_curl(self):
        result = self.run_script(starter=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("curl-download", self.events())
        self.assertIn("install-called", self.events())

    def test_failed_download_is_never_executed(self):
        result = self.run_script(starter=True, TEST_CURL_FAIL="1")
        self.assert_stopped_before_install(result)
        self.assertNotIn("partial-script-executed", self.events())

    def test_root_denied_has_no_package_side_effects(self):
        result = self.run_script(TEST_ROOT_DENIED="1")
        self.assert_stopped_before_install(result)
        self.assertNotIn("pkg ", self.events())
        self.assertNotIn("apt-get ", self.events())

    def test_unsupported_architecture_stops_before_root(self):
        result = self.run_script(TEST_ARCH="armeabi-v7a")
        self.assert_stopped_before_install(result)
        self.assertEqual(self.events(), "")

    def test_package_failure_does_not_clone(self):
        result = self.run_script(TEST_PKG_FAIL="upgrade")
        self.assert_stopped_before_install(result)
        self.assertNotIn("git clone", self.events())

    def test_curl_recovery_failure_stops(self):
        result = self.run_script(TEST_APT_FAIL="1")
        self.assert_stopped_before_install(result)
        self.assertNotIn("pkg ", self.events())

    def test_clone_failure_never_runs_partial_checkout(self):
        result = self.run_script(TEST_CLONE_FAIL="1")
        self.assert_stopped_before_install(result)
        self.assertFalse((self.home / "deepseek-harness-android").exists())

    def test_existing_unrelated_directory_is_preserved(self):
        repo = self.home / "deepseek-harness-android"
        repo.mkdir()
        sentinel = repo / "user-file"
        sentinel.write_text("keep")
        self.assert_stopped_before_install(self.run_script())
        self.assertEqual(sentinel.read_text(), "keep")

    def test_dirty_repository_is_not_fetched_or_overwritten(self):
        repo = self.seed_repo()
        before = (repo / "install-phone.sh").read_bytes()
        result = self.run_script(TEST_DIRTY=" M install-phone.sh")
        self.assert_stopped_before_install(result)
        self.assertNotIn(" fetch ", self.events())
        self.assertEqual((repo / "install-phone.sh").read_bytes(), before)

    def test_clean_repository_only_fast_forwards(self):
        self.seed_repo()
        result = self.run_script("--no-open")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("merge --ff-only origin/main", self.events())
        self.assertNotIn("phone open", self.events())

    def test_local_commit_is_not_reset(self):
        self.seed_repo()
        result = self.run_script(TEST_LOCAL_COMMITS="1")
        self.assert_stopped_before_install(result)
        self.assertNotIn("merge --ff-only", self.events())
        self.assertNotIn("reset", self.events())

    def test_existing_phone_install_is_not_reinstalled_or_opened(self):
        result = self.run_script(TEST_INSTALL_EXIT="17")
        self.assertEqual(result.returncode, 17)
        self.assertNotIn("phone open", self.events())
        self.assertIn("未重装", result.stderr)

    def test_install_failure_does_not_open_browser(self):
        result = self.run_script(TEST_INSTALL_EXIT="1")
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("phone open", self.events())

    def test_browser_failure_keeps_successful_install(self):
        result = self.run_script(TEST_OPEN_EXIT="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("安装已完成", result.stderr)

    def test_non_termux_environment_is_rejected(self):
        (self.bin / "pkg").unlink()
        self.assert_stopped_before_install(self.run_script())
        self.assertEqual(self.events(), "")


if __name__ == "__main__":
    unittest.main(verbosity=2)
