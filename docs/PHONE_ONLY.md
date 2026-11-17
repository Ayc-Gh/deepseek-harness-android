# 不使用电脑：Termux + root

这条入口在手机上下载、校验、部署 Ubuntu chroot，并启动同一套 Harness 服务。不需要 ADB，不安装 Windows PowerShell 脚本。

**验证范围：**原有 ADB 部署和 Harness 功能已经实机验证。新增手机入口完成了语法、已有安装保护、固定下载值一致性和现有服务状态查询检查；尚未在全新手机的 Termux 中执行完整安装，也没有验证 Termux 启动后的长期后台表现。预检查通过不等于全部兼容性通过。

独立一键入口 `install.sh` 另通过了 16 项隔离模拟测试及实机 root 误用拒绝检查，详见 [bootstrap-checks.json](../results/bootstrap-checks.json)。模拟测试没有真的安装或升级 Termux 软件包。

## 前提

- 手机已有 root，能给 Termux 授予 `su` 权限。
- ARM64 Android，并支持脚本所需的 mount namespace、chroot 和设备节点。
- 安装 Chrome，手机和下载站点、软件仓库、模型 API 之间网络可用。
- 准备数 GiB 空间；原机安装后的 Linux 环境约 2.3 GiB，还需要下载及安装临时空间。

没有 root 的手机不能使用这套安装器。Termux 原生使用 Android 的 bionic，本方案通过 root chroot 提供 Ubuntu/glibc 用户空间；这里没有验证 proot 替代方案。[Termux 官方环境说明](https://github.com/termux/termux-packages/wiki/Termux-execution-environment)

## Termux 刚安装好：一条命令安装

先安装官方 Termux，第一次打开后等待初始化完成、出现终端提示符。然后在普通 Termux 中粘贴下面整条命令，不用先安装 Git、手动选择项目目录或输入 `su`。仍然需要手机预先 root；root 授权弹窗和 API Key 输入需要自己完成。

<!-- one-click-command -->
```bash
bash -c 'set -e; (( EUID != 0 )) || { echo "请在普通 Termux 中运行"; exit 1; }; test -n "${PREFIX:-}" && test -x "$PREFIX/bin/apt-get" && test -x "$PREFIX/bin/pkg" || { echo "请先完成 Termux 首次初始化"; exit 1; }; export DEBIAN_FRONTEND=noninteractive; command -v curl >/dev/null || { apt-get update; apt-get install -y -o Dpkg::Options::=--force-confold curl ca-certificates; }; curl --fail --location --proto =https --proto-redir =https --retry 3 https://raw.githubusercontent.com/Ayc-Gh/deepseek-harness-android/main/install.sh -o "$PREFIX/tmp/dsh-install.sh"; bash "$PREFIX/tmp/dsh-install.sh"'
```

独立入口文件：[install.sh](../install.sh)。上面的启动命令会在 curl 缺失时先通过 APT 补齐下载工具；仅在脚本下载成功后执行，不把下载流直接交给 shell 执行。

`install.sh` 自动检查普通 Termux / ARM64 / root，更新 Termux 软件包并保留已有配置，安装 Git、curl、coreutils、CA 证书，再获取项目，调用原来的手机安装器，完成后尝试打开 Chrome。只安装、不自动打开浏览器时，可以对已下载的文件执行 `bash "$PREFIX/tmp/dsh-install.sh" --no-open`。

安装脚本不会申请共享存储权限、修改 root 管理器设置、关闭 SELinux或配置开机自启。无需 Termux:API 插件。脚本只适用于官方 Termux 的 APT 环境；不要在 `su` 提示符或 proot 容器里运行。

重复运行时，已有 Git 项目必须来源匹配、位于 main 分支且没有未提交文件/本地分叉，才会快进更新；其他目录和修改保持不变。已有手机安装目录仍会被下层安装器拒绝覆盖，退出码为 17，随后显示管理已有安装的方法。网络/包管理器/克隆/校验失败时停止，不继续执行部分下载的项目。

自动化回归测试见 [tests/test_bootstrap.py](../tests/test_bootstrap.py)：通过隔离 PATH 和模拟包管理器、Git、su 验证依赖缺失与失败分支，不会在测试中真的安装系统包。这些测试不等于在全新 Termux 应用或其他手机上完成端到端安装。

## 手动分步安装

从 [Termux 官方安装说明](https://github.com/termux/termux-app#installation) 选择官方 GitHub Releases 或 F-Droid 来源安装 Termux。打开 Termux，下面的命令都在**普通 Termux 提示符**执行，不要先进入 `su`：

```sh
pkg update
pkg install git curl coreutils
cd ~
git clone https://github.com/Ayc-Gh/deepseek-harness-android.git
cd deepseek-harness-android
bash install-phone.sh --check
bash install-phone.sh
```

root 管理器弹窗时允许 Termux。`--check` 检查 root、架构、Android 工具、挂载命名空间和目标目录；不下载或安装。不希望单独预检查时，可以直接运行不带 `--check` 的安装命令。

安装器会：

1. 在普通 Termux 中下载固定版本 Ubuntu、Node.js，使用仓库固定的官方 SHA256 值校验；失败则停止。
2. 进入 root 阶段，再次校验归档，然后创建全新的 `/data/local/dsh-verify-20261117-a1`。
3. 在执行 Android 和 Ubuntu 工具前清空 Termux 的环境变量，包括动态加载器变量，并使用 Android 系统命令 PATH。
4. 安装依赖和官方 Harness npm 包；服务以 UID 2000、零 Linux capabilities 运行。
5. 运行 8 项原生依赖与功能检查，全部通过后启动服务。

看到 8 项 `pass: true` 和 `Ready` 后再继续。安装器不获取 root、不修改 SELinux、不调整 Harness 权限策略、不配置开机自启，也不会覆盖已有安装。

出现 `Installation directory already exists` 时，已有目录保持不变。如果是完整安装，使用后面的启停命令。如果是失败后留下的部分安装，先查看错误并诊断；不要删除数据或反复强制覆盖。

## 第一次打开

```sh
bash phone.sh open
```

手机保持解锁。脚本从 root 保护的启动日志读取认证 URL，在 Chrome 打开，并执行一次直接地址栏导航，处理原机遇到的 Cookie 跳转问题；不会打印认证令牌。不同 Chrome/Android 版本仍可能需要你在地址栏手动输入 `http://127.0.0.1:3080/`。

在 Harness 模型设置中配置自己的 DeepSeek API Key，选模型，再新建会话。模型通过 API 联网调用，终端命令和文件操作发生在手机的 Linux 环境中。可用这个小任务验证：

> 只在 /home/dsh/workspace/demo 中创建 hello.py，让它打印 Hello，运行它并报告结果。

先保持默认权限。若执行命令出现 `SANDBOX_UNAVAILABLE`，需要判断该手机是否缺少可用 Landlock；原机属于这种情况。使用完全权限模式会失去对应的 Harness 命令沙箱限制，UID 2000 和 chroot 不是完整安全沙箱。参见 [权限说明](../README.md#先了解限制)。

## 日常使用

每次打开 Termux 后先进入仓库目录：

```sh
cd ~/deepseek-harness-android
bash phone.sh start
bash phone.sh open
```

查看或停止服务：

```sh
bash phone.sh status
bash phone.sh stop
```

服务已经运行且浏览器已登录时，直接用 Chrome 访问 `http://127.0.0.1:3080/` 即可，也可以将它加入书签。打开网页本身不会启动服务；手机重启后需要再次 `start`。

没有必要在已部署的原手机上重装。只需要在 Termux 克隆这个仓库，即可使用 `phone.sh` 管理原来的安装。

工作文件位于 Linux 环境的 `/home/dsh/workspace`。不要把整个 rootfs、`.dsh`、启动日志或登录 URL 上传到 GitHub。不要将“短时间能够运行”理解为“所有 Android 后台管理策略下都能持续运行”。

## 脚本入口

- `install-phone.sh`：普通 Termux 中运行，检查、下载、请求 root 安装。
- `install.sh`：从刚完成初始化的 Termux 开始，自动准备包管理器、依赖和项目，然后调用 `install-phone.sh`。
- `scripts/install-rootfs.sh`：内部 root 阶段入口，不应直接作为普通 Termux 安装命令运行。
- `scripts/assets.sh`：固定的官方下载 URL、文件名、SHA256，与 `results/official-downloads.json` 对应。
- `phone.sh`：请求 root 后执行启停、状态检查或打开浏览器。

DNS 默认使用 `223.5.5.5` 和 `1.1.1.1`。如果所在网络无法访问这两个 DNS，需要根据安装错误调整 rootfs 的解析配置，不能以关闭 SELinux或移除权限检查作为通用处理方法。
