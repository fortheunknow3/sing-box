# sing-box 一键安装与管理脚本（HY2 扩展版）

基于 [233boy/sing-box](https://github.com/233boy/sing-box) 修改，保留一键安装、`sb` / `sing-box` 命令、交互菜单、多节点管理和原有协议支持。本分支新增 Hysteria2 混淆、初始 QUIC 报文大小及路径 MTU 探测设置，并在修改端口、密码和执行 `fix` / `fix-all` 时保留这三项设置。

原作者：233boy。本分支：fortheunknow3。沿用 [GPL-3.0](LICENSE) 许可证。

## 一键安装

以 **root** 运行，支持上游脚本已有的 Ubuntu、Debian、CentOS、SUSE、Alpine，架构为 amd64 或 arm64：

```bash
(tmp=$(mktemp) && trap 'rm -f "$tmp"' EXIT && wget --timeout=20 --tries=2 -O "$tmp" https://raw.githubusercontent.com/fortheunknow3/sing-box/main/install.sh && test -s "$tmp" && bash "$tmp")
```

系统需要先有 Bash 和 wget。Alpine 可先运行 `apk add bash wget`，再进入 Bash 执行上面的命令。

下载失败会显示错误并停止，不会把空内容当成安装脚本执行。旧的 `bash <(wget -qO- ...)` 写法在 DNS 或下载失败时可能表现为“无反应”；此时先检查 `getent ahostsv4 raw.githubusercontent.com` 和 `/etc/resolv.conf`，确认实际可用的 DNS，再重试。不要直接套用某个公共 DNS；不同机房的连通性可能不同。

如果重启后失效，先检查 `systemctl status sing-box` 和 `journalctl -u sing-box -b`，保留配置再处理。**卸载会删除 `/etc/sing-box`，也会删除放在该目录内的备份**。卸载前应把需要保留的节点、证书和备份复制到此目录之外的受控位置。

安装会自动下载官方 sing-box 核心及依赖，创建服务，并生成一个 HY2 节点。首次安装默认不启用混淆，报文大小和 MTU 探测沿用核心默认值。安装完成后用 `sb` 打开菜单，或按下文修改节点。

本分支的安装和脚本更新均从 **fortheunknow3/sing-box** 获取源码，不依赖 GitHub Release 产物是否生成。核心仍从 **SagerNet/sing-box** 下载。

也可以从源码安装：

```bash
wget https://github.com/fortheunknow3/sing-box/archive/refs/heads/main.tar.gz -O sing-box-main.tar.gz
tar -xzf sing-box-main.tar.gz
cd sing-box-main
bash install.sh --local-install
```

原有安装参数仍可使用：`--core-version v1.14.4`、`--core-file /path/to/core.tar.gz`、`--proxy http://127.0.0.1:2333`、`--local-install`。运行 `bash install.sh --help` 查看详情。

## 从 233boy 原版迁移

已安装本分支的用户直接运行 `sb update sh`。原版的更新源仍指向 233boy，需要先替换管理脚本一次。以下命令备份并替换 **脚本目录**，不重装核心、不重建节点，也不重启服务：

```bash
(
    set -e
    test -f /etc/sing-box/sh/sing-box.sh
    workdir=$(mktemp -d)
    trap 'rm -rf "$workdir"' EXIT
    wget -qO "$workdir/source.tar.gz" https://github.com/fortheunknow3/sing-box/archive/refs/heads/main.tar.gz
    mkdir "$workdir/source"
    tar -xzf "$workdir/source.tar.gz" --strip-components=1 -C "$workdir/source"
    for file in "$workdir/source/"*.sh "$workdir/source/src/"*.sh; do bash -n "$file"; done
    backup="/etc/sing-box/sh.backup-$(date +%Y%m%d-%H%M%S)"
    cp -a /etc/sing-box/sh "$backup"
    cp -a "$workdir/source/sing-box.sh" "$workdir/source/install.sh" "$workdir/source/src" /etc/sing-box/sh/
    chmod +x /etc/sing-box/sh/sing-box.sh
    printf '脚本已更新，原脚本备份：%s\n' "$backup"
)
sb version
```

原有手动添加的 HY2 `obfs`、`initial_packet_size`、`disable_path_mtu_discovery` 会在后续读取和修改时保留。其他手工扩展字段不在本次保留范围内；修改前请自行备份包含这些字段的节点。

## 添加 HY2 节点

原来的命令保持兼容：

```bash
sb add hy2 22213 '认证密码'
```

同时设置混淆和报文参数：

```bash
sb add hy2 22213 '认证密码' \
  --obfs salamander \
  --obfs-password '独立的混淆密码' \
  --initial-packet-size 1200 \
  --mtu-discovery off
```

不指定混淆密码或使用 `--obfs-password auto` 时，会随机生成密码。认证密码与混淆密码是两个独立参数。密码包含空格、`&`、引号等字符时，请按 Bash 规则正确引用。

| 参数 | 可选值 | 行为 |
| --- | --- | --- |
| `--obfs` | `off`、`salamander`、`gecko` | 新节点默认为关闭；Gecko 要求核心和客户端支持 |
| `--obfs-password` | 密码或 `auto` | 配合混淆类型使用；修改已有同类型混淆且省略密码时保留原密码 |
| `--initial-packet-size` | `auto` / `0`，或 `1200`–`1452` | 单位字节；`auto` / `0` 删除显式字段，采用核心默认值；范围是本脚本的保守输入限制 |
| `--mtu-discovery` | `on`、`off`、`auto` | `off` 写入 `disable_path_mtu_discovery: true`；`on` 写入 `false`；`auto` 删除字段 |
| `--disable-path-mtu-discovery` | `true`、`false`、`auto` | 直接按核心字段语义设置；`true` 等价于 `--mtu-discovery off` |

报文大小、显式 MTU 探测开关及 Gecko **需要 sing-box 1.14.0 或以上**。旧核心仍可使用默认 HY2 和 Salamander；设置不支持的选项时，脚本会拒绝修改并提示 `sb update core`。

不要同时传入两个含义相反的 MTU 开关；若重复传入，以最后一个为准。省略选项时，新节点沿用核心默认值，修改已有节点则保留原设置。

`1200 + 关闭探测` 适合用来排查中转链路的大报文问题，不是所有网络的最佳设置，也不保证解决运营商限速。`initial_packet_size` 是 QUIC 报文大小，**不是网卡或 TUN MTU**；关闭探测后，QUIC 不再向上探测更大报文，混淆和 IP/UDP 头仍有额外开销。

## 修改已有 HY2 节点

`name` 可使用原脚本的文件名、端口或匹配关键词；匹配多个节点时会提示选择。以下以端口 `22213` 为例：

```bash
# 开启 / 修改混淆，或生成新密码
sb obfs 22213 salamander '独立的混淆密码'
sb obfs 22213 salamander auto

# 修改报文大小，关闭路径 MTU 探测
sb packet-size 22213 1200
sb mtu-discovery 22213 off

# 恢复核心默认值，关闭混淆
sb packet-size 22213 auto
sb mtu-discovery 22213 auto
sb obfs 22213 off
```

也支持完整形式及单次修改多个设置：

```bash
sb change 22213 obfs salamander '独立的混淆密码'
sb change 22213 packet-size 1200
sb change 22213 mtu-discovery off
sb full 22213 auto auto --obfs salamander --obfs-password auto --initial-packet-size 1200 --mtu-discovery off
```

`full` 的两个位置参数仍是新端口和认证密码；`auto auto` 在修改已有 HY2 时保留当前值。常规的 `sb port`、`sb passwd`、`sb full`、`sb fix` 和 `sb fix-all` 会保留这三项 HY2 设置；切换到其他协议后不再应用 HY2 参数。

运行 `sb` → **更改配置** → 选择 HY2 节点，可看到“更改 HY2 混淆”“更改 HY2 初始报文大小”“更改 HY2 路径 MTU 探测”。省略上述修改命令的值也会提示输入。通过主菜单添加 HY2 时会依次询问这三项；直接使用命令行添加则保持原来的快速、无需交互的行为。

HY2 候选配置会先通过 `sing-box check`，再替换原文件。参数不合法或核心检查失败时保留原配置；成功修改会按原脚本行为重启 sing-box 服务。

## 查看、导入客户端与回退

```bash
sb info 22213
sb url 22213
sb qr 22213
```

节点信息会显示混淆类型、混淆密码、初始报文大小及 MTU 探测状态。URL / QR 中会附带 `obfs` 和 `obfs-password`，特殊字符经过百分号编码。

客户端必须使用与服务端一致的混淆类型和密码。**服务端报文大小和 MTU 探测设置不会通过标准 HY2 分享链接下发**，也不要求客户端填写相同的值；如需调整客户端发包行为，在客户端单独配置对应字段。GUI for sing-box 用户可导入新链接，或在节点编辑页设置相同的混淆类型及密码。客户端若不支持 Gecko，请选 Salamander。

本脚本沿用上游的自签名证书及相关链接参数；证书设置按你的部署需求单独管理。调整服务端混淆后，需要同步客户端；只调整服务端报文参数时，可重连节点后复测。

仅生成 JSON、检查结果而不保存节点：

```bash
sb gen hy2 22213 '认证密码' --obfs salamander --obfs-password '独立的混淆密码' --initial-packet-size 1200 --mtu-discovery off
```

要撤销报文设置，运行 `sb packet-size 22213 auto` 和 `sb mtu-discovery 22213 auto`。要撤销混淆，先确认客户端也将关闭混淆，再运行 `sb obfs 22213 off`。

## 常用命令与更新

```bash
sb                       # 交互菜单
sb help                  # 完整帮助（含 HY2 扩展参数）
sb add reality           # 添加 VLESS-REALITY
sb add tuic              # 添加 TUIC
sb add trojan            # 添加 Trojan
sb info                  # 查看节点
sb port 22213 22214       # 修改端口，保留 HY2 扩展参数
sb passwd 22214 '新密码'  # 修改认证密码，保留 HY2 扩展参数
sb update core           # 更新官方核心
sb update sh             # 更新本分支脚本（main）
sb update sh 1.21        # 安装本仓库已存在的 v1.21 标签源码
sb status
sb restart
```

`sing-box` 与 `sb` 命令等价。TUIC、Trojan、AnyTLS、Shadowsocks 2022、VMess、VLESS、REALITY、Caddy 自动 TLS 及其他原有功能继续沿用上游实现。其余协议的教程可参考 [233boy 原文档](https://233boy.com/sing-box/sing-box-script/)；本分支 HY2 参数与安装地址以此 README 和 `sb help` 为准。

## 开发与测试

需要 Bash、jq、OpenSSL，以及带 QUIC 功能的 sing-box >= 1.14.0。测试使用独立临时目录，不需要 root，不读写已安装的 `/etc/sing-box`，不操作 systemd。

```bash
for file in install.sh sing-box.sh src/*.sh tests/*.sh; do bash -n "$file" || exit 1; done
SING_BOX_BIN=/absolute/path/to/sing-box bash tests/test-hy2.sh
bash tests/test-install.sh
```

回归覆盖原有 HY2 命令、参数校验、特殊字符密码、分享链接、随机混淆密码、版本限制、交互菜单、配置检查失败保护、端口/密码/full/fix/fix-all 保留，以及多节点与其他协议隔离。GitHub Actions 在测试成功后打包发布 `code.tar.gz`。

字段与链接定义参考：[sing-box QUIC 字段](https://sing-box.sagernet.org/configuration/shared/quic/)、[HY2 入站配置](https://sing-box.sagernet.org/configuration/inbound/hysteria2/)、[Hysteria 2 URI 规范](https://v2.hysteria.network/docs/developers/URI-Scheme/)。
