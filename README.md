# VMess/VLESS + Argo 极简一键脚本

本项目提供一个 **全功能一键脚本**，用于快速部署 **VMess/VLESS + Argo**。  
特点：轻量、自动化、跨系统支持、无需域名、支持伪装域名、自动检测 NAT VPS、带守护进程检测与自恢复功能，并自动生成客户端配置文件。

---

## 功能特性
- 自动安装 **v2ray** 与 **cloudflared**
- 自动生成 **UUID** 与随机 **WebSocket 路径**
- 支持 **VMess / VLESS / 双协议**
- 支持 **Argo Quick Tunnel** 或 **自定义伪装域名**
- 自动检测 VPS 是否为 **NAT 类型**
- 自动检测系统类型（Alpine / Debian / Ubuntu / CentOS / Fedora）
- 输出客户端配置参数（UUID、WS 路径、域名）
- 自动生成客户端配置文件（Clash Meta / V2RayNG / Sing-box）
- 内置守护脚本，自动检测进程是否停止并重启

---

## 使用方法

### 1. 下载并运行脚本
```sh
wget -O install.sh https://raw.githubusercontent.com/als168/VMess-Argo/main/install.sh
sh install.sh
```
2. 获取配置参数
脚本运行后会输出：

UUID

WS 路径

域名（Argo 随机域名或自定义伪装域名）

NAT VPS 检测结果

系统类型

同时会在 /root/clients/ 目录生成客户端配置文件：

clash-meta.yaml

v2rayng.json

sing-box.json
