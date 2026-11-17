# 安装与复现

本文记录 2026-11-17 在 OPPO PHY110 上完成的部署流程。上游软件没有修改；本仓库提供 Android 启动适配、功能检查及运行说明。不同 root 实现、内核、Android 网络策略可能产生不同结果。

本文使用电脑和 ADB；如果只有手机，请使用 [Termux 手机端安装说明](PHONE_ONLY.md)。

## 1. 前提与版本

需要 ARM64 Android 手机、已有 root、已授权 ADB、可用网络和数 GiB 可用空间。**下列直接 `adb push` 到受保护目录的步骤以 `adb shell id -u` 返回 `0` 为前提。** 若只能通过 `su` 提权，需要自行把上传文件先放到可写的暂存目录，再在 root shell 中移动；这条变体未在本次验证中执行。

本次固定版本：

- [Ubuntu Base 官方目录](https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/)：`ubuntu-base-24.04.5-base-arm64.tar.gz`
- [Node.js 官方目录](https://nodejs.org/dist/v24.22.3/)：`node-v24.22.3-linux-arm64.tar.gz`
- [Harness 官方仓库](https://github.com/deepseek-ai/deepseek-harness)：`@deepseek-ai/dsh@0.2.2-rc.1`
- [npm 官方注册表元数据](https://registry.npmjs.org/@deepseek-ai%2fdsh/0.2.2-rc.1)

Harness 包声明 Node.js `>=24.9.0`。保留了此次查询的 npm 包版本和完整性信息：[official-package-metadata.json](../results/official-package-metadata.json)。固定顶层包版本不代表 apt 包和所有传递依赖永久可复现；本仓库没有打包安装后的运行环境。

电脑安装 [Platform-Tools](https://developer.android.com/tools/releases/platform-tools)，从仓库根目录打开 PowerShell。先用 `adb devices` 查看设备，并按需要设置：

```powershell
adb devices
# 有多台设备时填写实际序列号；不要把它写回本仓库。
$env:ANDROID_SERIAL = 'YOUR_DEVICE_SERIAL'
adb shell id -u
adb shell getprop ro.product.cpu.abi
```

预期为 `0` 和 `arm64-v8a`。本方案不提供获取 root 的步骤，也不要求关闭 SELinux。

## 2. 下载与 SHA256 校验

在电脑 PowerShell 执行，所有内容来自官方 HTTPS 站点：

```powershell
New-Item -ItemType Directory -Force .downloads | Out-Null
$ubuntuName = 'ubuntu-base-24.04.5-base-arm64.tar.gz'
$nodeName = 'node-v24.22.3-linux-arm64.tar.gz'
$ubuntuUrl = 'https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release'
$nodeUrl = 'https://nodejs.org/dist/v24.22.3'
Invoke-WebRequest "$ubuntuUrl/$ubuntuName" -OutFile ".downloads/$ubuntuName"
Invoke-WebRequest "$ubuntuUrl/SHA256SUMS" -OutFile '.downloads/ubuntu-SHA256SUMS'
Invoke-WebRequest "$nodeUrl/$nodeName" -OutFile ".downloads/$nodeName"
Invoke-WebRequest "$nodeUrl/SHASUMS256.txt" -OutFile '.downloads/node-SHASUMS256.txt'

function Assert-OfficialHash($Name, $Manifest) {
  $lines = @(Get-Content -LiteralPath $Manifest | Where-Object {
    $parts = $_.Trim() -split '\s+'
    $parts.Count -eq 2 -and $parts[1].TrimStart('*') -eq $Name
  })
  if ($lines.Count -ne 1) { throw "Missing or ambiguous official hash: $Name" }
  $expected = ($lines[0].Trim() -split '\s+')[0]
  $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath ".downloads/$Name").Hash
  if ($actual -ne $expected) { throw "SHA256 mismatch: $Name" }
  Write-Host "SHA256 OK: $Name"
}
Assert-OfficialHash $ubuntuName '.downloads/ubuntu-SHA256SUMS'
Assert-OfficialHash $nodeName '.downloads/node-SHASUMS256.txt'
```

GNU 校验清单可能在文件名前带 `*`；上面的解析会去掉它。本次做的是与官方 HTTPS 清单比对 SHA256，没有将其描述为独立的 GPG 签名验证。

## 3. 新建目录与解压

进入 `adb shell`，确认 UID 为 0，然后执行以下 Android shell 命令。**目标目录已存在时停止，不能用这一步覆盖已有安装。** 已安装用户从第 6 节开始使用即可。

```sh
set -eu
BASE=/data/local/dsh-verify-20261117-a1
test ! -e "$BASE" || { echo 'Target already exists; do not overwrite.' >&2; exit 1; }
umask 077
mkdir -p "$BASE/rootfs" "$BASE/downloads" "$BASE/scripts" "$BASE/logs"
printf '%s\n' dsh-verification-20261117-a1 > "$BASE/.verification-owner"
exit
```

回到电脑 PowerShell 上传文件：

```powershell
$base = '/data/local/dsh-verify-20261117-a1'
adb push '.downloads/ubuntu-base-24.04.5-base-arm64.tar.gz' "$base/downloads/"
adb push '.downloads/node-v24.22.3-linux-arm64.tar.gz' "$base/downloads/"
Get-ChildItem scripts -Filter '*.sh' | ForEach-Object { adb push $_.FullName "$base/scripts/" }
```

再次进入手机 `adb shell`：

```sh
set -eu
BASE=/data/local/dsh-verify-20261117-a1
ROOTFS="$BASE/rootfs"
test "$(cat "$BASE/.verification-owner")" = dsh-verification-20261117-a1
tar -xzf "$BASE/downloads/ubuntu-base-24.04.5-base-arm64.tar.gz" -C "$ROOTFS"
tar -xzf "$BASE/downloads/node-v24.22.3-linux-arm64.tar.gz" -C "$ROOTFS/usr/local" --strip-components=1
mkdir -p "$ROOTFS/proc" "$ROOTFS/dev" "$ROOTFS/tmp"
chmod 1777 "$ROOTFS/tmp"
# 替换该新建 rootfs 内的 DNS 配置；按实际网络修改 DNS 地址。
rm -f "$ROOTFS/etc/resolv.conf"
printf 'nameserver 223.5.5.5\nnameserver 1.1.1.1\n' > "$ROOTFS/etc/resolv.conf"
chmod 644 "$ROOTFS/etc/resolv.conf"
chmod 700 "$BASE/scripts/"*.sh
cp "$BASE/scripts/bootstrap-linux.sh" "$ROOTFS/root/bootstrap-linux.sh"
"$BASE/scripts/enter-chroot.sh" admin /bin/bash /root/bootstrap-linux.sh
exit
```

`bootstrap-linux.sh` 安装基础依赖，创建 UID/GID 2000 的 `dsh` 用户及附加组 3003，准备运行目录，并禁止 apt 安装期间自动启动系统服务。它是首次安装脚本，不是可重复执行的升级脚本。

## 4. 安装 Harness 并检查原生依赖

电脑 PowerShell：

```powershell
$base = '/data/local/dsh-verify-20261117-a1'
adb push scripts/install-harness.sh "$base/rootfs/home/dsh/install-harness.sh"
adb push scripts/start-harness.sh "$base/rootfs/home/dsh/start-harness.sh"
adb push tests/native-smoke.cjs "$base/rootfs/home/dsh/runtime/native-smoke.cjs"
```

手机 `adb shell`：

```sh
set -eu
BASE=/data/local/dsh-verify-20261117-a1
chown 2000:2000 "$BASE/rootfs/home/dsh/install-harness.sh" "$BASE/rootfs/home/dsh/start-harness.sh" "$BASE/rootfs/home/dsh/runtime/native-smoke.cjs"
chmod 700 "$BASE/rootfs/home/dsh/install-harness.sh" "$BASE/rootfs/home/dsh/start-harness.sh"
"$BASE/scripts/enter-chroot.sh" user /bin/bash /home/dsh/install-harness.sh
"$BASE/scripts/enter-chroot.sh" user /usr/local/bin/node /home/dsh/runtime/native-smoke.cjs
exit
```

预期 8 项检查均为 `pass: true`。测试只在本环境的 `/home/dsh/workspace/smoke` 中创建文件，结果写入 `/home/dsh/native-smoke-results.json`。其中原生模块从脚本所在的 `runtime/node_modules` 解析，所以应保留上面的位置。

## 5. 首次启动与 API Key

电脑 PowerShell：

```powershell
.\harness.ps1 start
.\harness.ps1 status
.\harness.ps1 open
```

如果 `adb` 不在 PATH：

```powershell
.\harness.ps1 open -Adb 'C:\Android\platform-tools\adb.exe' -Serial '<实际序列号>'
```

手机保持解锁。打开后通过 Harness 自己的模型配置界面填写 DeepSeek API Key。不要将 Key 放入本仓库、命令记录、Issue 或截图中。

服务监听手机环回地址；`logs/web.log` 内有带令牌的首次登录 URL。控制脚本读取该 URL 打开手机 Chrome，并隐藏终端输出中的令牌。若手动打开该 URL 后出现 401，在浏览器地址栏**直接输入** `http://127.0.0.1:3080/` 再进入。此行为在本机已复现并验证；保留上游 Cookie 认证，没有用匿名访问绕过它。

模型通过 API 调用；服务与命令工具运行在手机。默认 `workspace-write` 沙箱在本机因 Landlock 不可用而拒绝命令，这是正常的失败保护。需要执行命令时，在理解 [README 的权限限制](../README.md#先了解限制) 后自行选择适当的 Harness 权限/审批策略。本仓库不写入 `danger-full-access` 或 `never` 配置；验收记录如实记录了当时使用的模式。

## 6. 日常启停与重启恢复

Windows：

```powershell
.\harness.ps1 start
.\harness.ps1 open
.\harness.ps1 status
.\harness.ps1 stop
```

手机 root 终端也可以直接执行：

```sh
/data/local/dsh-verify-20261117-a1/scripts/service.sh start
/data/local/dsh-verify-20261117-a1/scripts/service.sh status
/data/local/dsh-verify-20261117-a1/scripts/service.sh stop
```

`stop` 发送 SIGTERM；重新启动前等待 `status` 返回 `Not running`。PID 文件会结合 `/proc/<pid>/root` 检查，不会仅凭旧 PID 停止任意宿主进程。当前没有开机自启，手机重启后需要重新 `start`。

工作区在 rootfs 的 `/home/dsh/workspace`。配置、凭据、会话在用户运行目录中，均不属于公开仓库；不要直接打包整个安装目录分享。

## 7. 挂载与网络注意事项

启动器创建新的挂载命名空间，并通过 **Ubuntu util-linux 的 mount** 执行 `--make-rprivate /`；随后检查挂载信息中没有 `shared:` 才继续。`proc` 和最小 `/dev` 仅在私有空间挂载。

本次初始兼容测试曾因 Android toybox mount 对参数的处理差异造成异常挂载任务；经过明确授权的手机重启清除后，改用了当前实现。**不要用 toybox 的其他挂载语法猜测替代私有传播设置，也不要把 Android 根目录反复 bind 到自身。** 若私有化检查失败，停止部署并检查内核/工具兼容性。

可在 Android 原始 root shell 中检查没有泄漏本次部署的挂载：

```sh
grep -c dsh-verify-20261117-a1 /proc/self/mountinfo
```

本次预期输出 `0`（grep 无匹配时退出码为 1，属于预期）。不要在 chroot 内用这条命令判断宿主状态。

本机任意新 UID（最初测试为 55001）即使加入组 3003，联网仍被 Android 拒绝；UID 2000 联网通过。因此采用 shell UID，而不是宣称它具有独立应用的隔离能力。其他机型应重新检查网络、SELinux、内核能力；不要以关闭 SELinux或授予全部 root 权限作为默认修复。

## 8. 验收范围

参考 [verification-results.json](../results/verification-results.json) 与 [native-smoke-results.json](../results/native-smoke-results.json)。60 秒息屏测试中，进程未退出；无 Cookie 的请求持续返回预期的 HTTP 401。它证明该时段服务仍能响应，不等同于模型在深度待机期间持续运行。长期断线、拔线、自动启动及跨机型支持仍需单独验证。
