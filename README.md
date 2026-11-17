# DeepSeek Harness on rooted Android

在有 root 权限的 ARM64 Android 手机上，用 Ubuntu chroot 运行 DeepSeek Harness 的实测脚本与中文复现记录。

**Harness 服务、终端和文件工具运行在手机本机，模型通过 DeepSeek API 调用。** 本项目是社区兼容方案，不代表 DeepSeek 官方提供 Android 支持，也不是离线模型推理项目。

上游入口：[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)。官方通过 npm 提供 Web UI，项目仍处于开发者预览阶段。这里固定到本次验证的版本，不自动升级。

## 实测环境

| 项目 | 本次验证值 |
| --- | --- |
| 验证日期 | 2026-11-17 |
| 手机 | OPPO PHY110 / SM8650 / ARM64 |
| Android | 17，API 37 |
| 内核 | 6.1.157，4 KiB 页面，SELinux Enforcing |
| root | 已有 root，ADB shell 为 UID 0 |
| Linux 用户空间 | Ubuntu Base 24.04.5 arm64 |
| Node.js | v24.22.3 linux-arm64 |
| Harness | `@deepseek-ai/dsh@0.2.2-rc.1` |
| 服务地址 | 手机 `http://127.0.0.1:3080/` |
| 运行身份 | UID/GID 2000，附加组 3003，Linux capabilities 清零 |

根文件系统及安装依赖约占 2.3 GiB；最后一次服务 RSS 约 351 MiB。这些是本次观测值，不是硬件最低要求或运行上限。

## 已验证

- 文件写入、读取、硬链接和重命名。
- Bash、Git、Python、ARM64 ripgrep。
- `sharp`、`koffi`、`node-pty`、原生文件锁。
- 真实模型完成文件读写、`id -u` 返回 `2000`、Python 计算返回 `42`。
- 手机 Chrome 显示界面，并打开此前完成的验收会话。
- 服务停止后重新启动，模型配置与会话保留。
- 手机重启后**手动启动**恢复；息屏 60 秒期间进程持续存活、认证接口持续响应。
- Android 主挂载命名空间中，本次部署的挂载数为 0；此前异常挂载任务已清除。

原始功能测试脚本见 [tests/native-smoke.cjs](tests/native-smoke.cjs)，脱敏结果见 [results/](results/)。未上传 API Key、浏览器 Cookie、登录 URL、设备序列号、运行时数据库或手机镜像。

## 先了解限制

1. **不是完整安全沙箱。** 这台手机的内核没有可用 Landlock；Harness 默认 `workspace-write` 命令沙箱会以 `SANDBOX_UNAVAILABLE` 拒绝执行。本次真实命令在 Harness `danger-full-access` 模式下完成，验收会话的审批策略为 `never`。脚本不自动修改你的 Harness 权限策略。
2. 服务降权到 UID 2000，清空 effective/bounding capabilities，设置 `no_new_privs`。UID 2000 与 Android shell 共用，不能理解为独立 Android 应用隔离；chroot 和私有挂载命名空间也不能代替完整安全沙箱。
3. 需要已有 root、`unshare -m`、chroot 及设备内核支持。没有关闭 SELinux，也没有把 Android 的整个 `/dev`、`/data`、`/sdcard` 绑定进 Linux。
4. 没有配置开机自启；未测试断开 USB 后长期运行、深度待机数小时或不同机型。
5. Web UI 保留上游认证，首次进入需要启动日志中的登录 URL。不要将该 URL 或包含它的日志公开。

## 安装与使用

完整步骤见 **[中文安装说明](docs/INSTALL.md)**。这是已验证环境的复现记录；整理后的安装流程未在第二台手机上执行完整重装，不是通用的一键安装器。

已安装完成后，在手机 root shell 执行：

```sh
/data/local/dsh-verify-20261117-a1/scripts/service.sh start
/data/local/dsh-verify-20261117-a1/scripts/service.sh status
/data/local/dsh-verify-20261117-a1/scripts/service.sh stop
```

Windows 上安装 [Android SDK Platform-Tools](https://developer.android.com/tools/releases/platform-tools)，将 `adb` 加入 PATH，然后在本仓库目录运行：

```powershell
.\harness.ps1 start
.\harness.ps1 open
.\harness.ps1 status
.\harness.ps1 stop
```

默认自动选择唯一一台处于 `device` 状态的手机；也可以指定 `-Serial <设备序列号>`、`-Adb <adb.exe完整路径>`。`open` 需要手机解锁，使用 Chrome；它处理本次实测出现的外部 Intent 跳转后 HTTP 401 问题，随后在地址栏直接进入主页，不修改服务端认证。

为保持与实测环境一致，脚本保留路径 `/data/local/dsh-verify-20261117-a1` 和所有者标记。若要改目录，需同步修改 `scripts/enter-chroot.sh`、`scripts/service.sh`、`harness.ps1` 和安装步骤；不要直接覆盖已有安装。

## 文件结构

```text
scripts/                 手机启动、降权、安装脚本
tests/native-smoke.cjs    8 项原生依赖与功能检查
results/                 脱敏验收结果、官方 npm 包元数据
harness.ps1              Windows ADB 启停与打开页面
docs/INSTALL.md          官方下载来源、校验、部署步骤、故障处理
```

本仓库自有脚本和文档采用 [MIT License](LICENSE)。DeepSeek Harness、Ubuntu、Node.js 及第三方依赖分别遵循各自许可证，本仓库不重新分发其二进制或模型权重。
