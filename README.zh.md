# apks2opencode

[English](README.md) | 中文

一套基于 Docker 的 APK 逆向分析环境。把 JADX 反编译、jrag 语义索引、OpenCode AI 助手串成流水线，让 AI 能理解反编译后的代码并追踪调用链。

**优势：**

- **一键部署**：`docker compose up` 拉起全套环境，不用逐个安装配置
- **自然语言分析**：不用手动翻代码，直接问"支付逻辑在哪"、"谁调用了这个函数"
- **语义搜索 + 调用链**：jrag 提供向量检索和图查询，比 grep 高效得多
- **全本地索引**：代码不离开机器，索引持久化，可增量更新

## 架构

```
┌──────────────────┐         ┌─────────────────┐
│  jadx-ai-mcp     │         │    opencode     │
│  JADX GUI (6080) │◀───────▶│    AI Agent     │
│  MCP Server(8651)│         │                 │
└──────────────────┘         └────────┬────────┘
                                      │
                             ┌────────▼────────┐
                             │      jrag       │
                             │  向量库 + 图库  │
                             │ (MCP via stdio) │
                             └─────────────────┘
```

- **jadx-ai-mcp**：提供 JADX GUI（noVNC）和 MCP HTTP 服务，用于精确反编译和 Android 专有信息
- **opencode**：AI Agent，通过 MCP 协议调用 jrag 和 jadx
- **jrag**：基于 jadx 源码构建的语义索引和调用图，随 opencode 一起安装

## 快速开始

### 依赖

- Docker + Docker Compose
- 一个 OpenAI 兼容的 API（DeepSeek、SiliconFlow、OpenAI 等）

### 启动

```bash
docker compose up -d --build
```

首次启动会：

1. 下载 evil-opencode 最新版二进制
2. 安装 jrag-cli（约 5-10 分钟）
3. 创建 dummy pom.xml（如果源码目录为空）
4. 构建初始索引

### 配置 API

进入 OpenCode TUI 后，用 `/connect` 命令配置 API：

```bash
docker attach opencode
```

在 TUI 里执行 `/connect`，选择你的提供商，粘贴 API Key 和 Base URL。凭据会持久化在 `opencode-data` 卷中，后续无需重复配置。

### 添加 APK

```bash
./add_apk.sh /path/to/your_app.apk
```

脚本会完成：复制 APK → jadx 反编译 → 源码添加到 `./repos/<apk名>/` → 重建索引。每个 APK 的源码放在独立子目录，多个 APK 即使包名相同也不会互相覆盖。

### 安装推荐 Skill（可选）

`install-skills.sh` 会为 OpenCode 装上一组逆向分析相关的 Skill（路由包 + 移动端静态分析）。Skill 只扩展 AI 的领域知识，不改动核心流水线。

在项目根目录的**宿主机**上执行——脚本会把 Skill 拷进运行中的 `opencode` 容器，并通过 `opencode-config` 卷持久化：

```bash
bash recommend-skills.sh
```

脚本会：

1. 定位运行中的 `opencode` 容器（未运行则自动启动）
2. 在宿主机 clone Skill 仓库
3. 拷进容器内的 `/root/.config/opencode/skills/`

安装的 Skill：

- `reverse-engineering`（来自 [zhaoxuya520/reverse-skill](https://github.com/zhaoxuya520/reverse-skill)）
- `mobile-reverse`（来自 [alvinhayy/Mobile-ReverseSkill](https://github.com/alvinhayy/Mobile-ReverseSkill)）

重启 OpenCode 生效：

```bash
docker compose restart opencode
```

进入 TUI 后问「现在有哪些可用的 skill？」即可验证。

> **注意**：执行 `docker compose down -v` 会删除 `opencode-config` 卷，已安装的 Skill 也会一并清除。重新跑 `install-skills.sh` 即可恢复。

### 使用

```bash
docker attach opencode
```

直接提问，例如：

```
这个 APP 里有哪些 Activity？
com.example.MainActivity 调用了哪些关键服务？
```

`/mcp list` 查看 MCP 连接状态。

## 可选配置

创建 `.env` 文件可覆盖以下默认值，**全部可选**：

```env
# JADX GUI 和 MCP 服务的对外端口
JADX_GUI_PORT=6080
JADX_MCP_PORT=8651

# jrag 嵌入模型，选择 HuggingFace 上的模型
SBERT_MODEL=sentence-transformers/all-MiniLM-L6-v2

# jrag 嵌入设备：cpu / cuda / mps
# 有 NVIDIA 显卡设为 cuda，苹果设备设为 mps
SBERT_DEVICE=cpu
```

## 已知坑

### 1. JADX 双 Token

JADX 有**两套独立 Token**：

| Token | 默认值 | 作用 |
|---|---|---|
| Plugin Token | `jadx-plugin-secret-token` | GUI 插件内部通信（8650） |
| MCP Admin Token | `admin-secret-token` | MCP Server 对外认证（8651） |

OpenCode 连接的是 MCP Server，必须用 Admin Token，格式为 `Bearer admin-secret-token`（注意空格）。

`init-opencode.sh` 已经配置好了默认值。如果自定义了 `JADX_MCP_AUTH_TOKEN`，需要同步修改 `init-opencode.sh` 中的 header。

### 2. jrag increment 检测不到新文件

`jrag increment` 只会更新已索引文件的变更，**不会扫描新增文件**。添加新 APK 后必须重建索引。

`add_apk.sh` 已内置此逻辑：先尝试 increment，如果文件数不变，自动 fallback 到全量 `jrag install`。

### 3. jadx GUI 需要手动加载 APK

MCP 服务起来后，JADX GUI 里如果没有打开 APK，工具查不到任何东西。浏览器访问 `http://<IP>:6080`，在 GUI 里打开 `/apks/xxx.apk`。

### 4. 跨 APK 的 FQN 冲突

子目录隔离只解决路径冲突，不解决 FQN（全限定类名）冲突。如果两个 APK 都有 `com.example.package.Class` 这个类，LadybugDB 建图时还是会报 `Symbol already exists`。

## 项目结构

```
.
├── docker-compose.yml
├── add_apk.sh              # 一键添加 APK
├── install-skills.sh       # 安装推荐 OpenCode Skill
├── .env                    # 可选配置
├── opencode/
│   ├── Dockerfile
│   └── init-opencode.sh
├── apks/                   # 放置 APK 文件
├── repos/                  # 反编译后的 Java 源码
│   ├── apk_1/
│   └── apk_2/
└── data/
    └── jrag-index/         # jrag 索引持久化
```

## 工作流建议

**给 AI 的提问模板**（省 Token）：

> 直接回答。只调用必要的工具，最多 1-2 次。不要做额外的状态验证。

**分析流程：**

1. `jrag search` 定位相关类
2. `jrag neighbors` / `callers` 追调用链
3. 需要精确源码时用 jadx MCP 或直接读 `/workspace/<apk名>/` 下的文件

**多 APK 管理**：每个 APK 的源码放在 `/workspace/` 下各自的子目录，即使包名相同也不会互相覆盖。

## 已知限制

- jadx GUI 一次只能加载一个 APK
- jrag 图查询不跨 APK
- 默认嵌入模型对中文语义理解有限，建议用英文关键词，或切换 `SBERT_MODEL` 为 `BAAI/bge-small-zh-v1.5`
- 大型 APK（10k+ 类）首次索引约 1 小时

## 致谢

本项目是以下工具的编排配置，核心功能均由上游提供：

- [evil-opencode](https://github.com/WinMin/evil-opencode)
- [jrag](https://github.com/HumanBean17/jrag)
- [jadx-ai-mcp](https://github.com/xjoker/jadx-ai-mcp)
- [jadx](https://github.com/skylot/jadx)

## License

MIT
