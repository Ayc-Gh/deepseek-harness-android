#!/usr/bin/env bash
# Standalone entry point: run in ordinary Termux after its first-run setup.
set -Eeuo pipefail
open_browser=true
case "${1:-}" in
  '') ;;
  --no-open) open_browser=false ;;
  --help|-h) printf 'Usage: bash install.sh [--no-open]\nRun in ordinary, initialized Termux on an already-rooted ARM64 phone.\n'; exit 0 ;;
  *) printf 'Unknown option. Usage: bash install.sh [--no-open]\n' >&2; exit 2 ;;
esac
phase='检查 Termux 环境'
fail() { printf '错误：%s\n' "$*" >&2; exit 1; }
on_error() {
  local code=$?
  printf '\n安装已停止：%s（退出码 %s）。请处理上方错误后重试。\n' "$phase" "$code" >&2
  exit "$code"
}
trap on_error ERR
(( EUID != 0 )) || fail '请退出 su，在普通 Termux 提示符中运行；不要用 root 运行 Termux 包管理器。'
[[ -n "${PREFIX:-}" && -x "$PREFIX/bin/pkg" && -x "$PREFIX/bin/apt-get" ]] || fail '需要已完成首次初始化的官方 Termux（APT 版本）。'
[[ -n "${HOME:-}" && -d "$HOME" ]] || fail 'Termux 用户目录不可用。'
case "$HOME" in /*) ;; *) fail 'Termux 用户目录必须是绝对路径。';; esac
case "$HOME" in *[!a-zA-Z0-9_./-]*) fail '请使用默认 Termux 用户目录，路径不能包含空格或特殊字符。';; esac
command -v getprop >/dev/null || fail '没有找到 Android getprop；请在手机 Termux 中运行。'
[[ "$(getprop ro.product.cpu.abi)" == arm64-v8a ]] || fail '当前安装方案要求 ARM64（arm64-v8a）。'
command -v su >/dev/null || fail '手机需要预先 root，并允许 Termux 使用 su。'

printf '[1/5] 检查 root 权限；手机弹窗时允许 Termux。\n'
phase='获取 root 授权'
if ! root_uid=$(su -c 'exec /system/bin/env -i PATH=/system/bin:/system/xbin:/vendor/bin /system/bin/id -u'); then
  fail 'root 授权失败。请在 root 管理器中允许 Termux 后重试。'
fi
[[ "$root_uid" == 0 ]] || fail 'su 没有返回 UID 0，不能继续安装。'

printf '[2/5] 准备 Termux 包管理器与依赖。\n'
phase='准备下载工具'
export DEBIAN_FRONTEND=noninteractive
# pkg mirror selection itself uses curl. Recover through apt directly if absent.
if ! command -v curl >/dev/null; then
  "$PREFIX/bin/apt-get" update
  "$PREFIX/bin/apt-get" install -y -o Dpkg::Options::=--force-confold curl ca-certificates
fi
phase='更新 Termux 软件包（保留已有配置）'
"$PREFIX/bin/pkg" update -y
"$PREFIX/bin/pkg" upgrade -y -o Dpkg::Options::=--force-confold
"$PREFIX/bin/pkg" install -y -o Dpkg::Options::=--force-confold git curl coreutils ca-certificates
hash -r
for tool in git curl sha256sum mktemp; do
  command -v "$tool" >/dev/null || fail "依赖未准备成功：$tool"
done

printf '[3/5] 获取部署项目。\n'
phase='获取 GitHub 项目'
repo_url=https://github.com/Ayc-Gh/deepseek-harness-android.git
repo_dir="$HOME/deepseek-harness-android"
if [[ -e "$repo_dir" || -L "$repo_dir" ]]; then
  [[ ! -L "$repo_dir" && -d "$repo_dir/.git" ]] || fail '项目路径已被其他目录或链接占用，已停止，未覆盖。'
  [[ "$(git -C "$repo_dir" remote get-url origin)" == "$repo_url" ]] || fail '已有目录的 GitHub 来源不匹配，未覆盖。'
  [[ -z "$(git -C "$repo_dir" status --porcelain)" ]] || fail '已有项目包含未提交文件，请先保存或处理；脚本不会覆盖本地修改。'
  [[ "$(git -C "$repo_dir" symbolic-ref --short HEAD)" == main ]] || fail '已有项目不在 main 分支，未切换分支或覆盖。'
  git -C "$repo_dir" fetch origin main
  git -C "$repo_dir" merge-base --is-ancestor HEAD origin/main || fail '已有项目含本地提交或分叉，未覆盖。'
  git -C "$repo_dir" merge --ff-only origin/main
else
  # Clone to a private temporary directory; a failed transfer is never executed.
  download_dir=$(mktemp -d "$HOME/.dsh-checkout.XXXXXXXX")
  git clone --depth 1 --branch main "$repo_url" "$download_dir/repo"
  mv -T --no-clobber -- "$download_dir/repo" "$repo_dir"
  [[ ! -e "$download_dir/repo" ]] || fail '目标目录在下载期间被创建，已停止，未覆盖。'
  rmdir -- "$download_dir"
fi
[[ -f "$repo_dir/install-phone.sh" && -f "$repo_dir/phone.sh" ]] || fail '获取的项目缺少安装或控制入口。'

printf '[4/5] 安装 Ubuntu、Node.js 和 Harness，并运行功能检查。\n'
phase='部署手机运行环境'
if bash "$repo_dir/install-phone.sh"; then
  :
else
  result=$?
  if [[ "$result" == 17 ]]; then
    printf '\n手机已有安装目录，已停止，未重装。完整安装可运行：\n  cd %s\n  bash phone.sh status\n  bash phone.sh start\n  bash phone.sh open\n部分安装请先处理原始错误。\n' "$repo_dir" >&2
  else
    printf '\n安装失败（退出码 %s）；保留现场，请根据上方错误处理。\n' "$result" >&2
  fi
  exit "$result"
fi

printf '[5/5] 安装完成。\n'
if "$open_browser"; then
  phase='打开手机 Chrome'
  if ! bash "$repo_dir/phone.sh" open; then
    printf '服务安装已完成，但浏览器未打开。安装 Chrome、解锁手机后运行 bash phone.sh open。\n' >&2
  fi
fi
printf '\n在 Harness 页面配置自己的 DeepSeek API Key。\n日常使用：\n  cd %s\n  bash phone.sh start\n  bash phone.sh open\n查看状态：bash phone.sh status\n停止服务：bash phone.sh stop\n手机重启后需要手动 start。\n' "$repo_dir"
