# apks2opencode

English | [中文](README.zh.md)

A Docker-based environment for APK reverse engineering and analysis. It integrates JADX (decompilation), jrag (semantic indexing), and the OpenCode AI assistant into a unified pipeline, enabling the AI to understand decompiled code and trace call chains.

**Advantages:**

- **One-click deployment**: `docker compose up` launches the entire environment; no need for manual installation or configuration.
- **Natural language analysis**: No need to manually sift through code; simply ask questions like "Where is the payment logic?" or "Who calls this function?"
- **Semantic search + Call chains**: jrag provides vector retrieval and graph queries, making it far more efficient than grep.
- **Fully local indexing**: Code never leaves your machine; the index is persistent and supports incremental updates.

## Architecture

```
┌──────────────────┐         ┌─────────────────┐
│  jadx-ai-mcp     │         │    opencode     │
│  JADX GUI (6080) │◀───────▶│    AI Agent     │
│  MCP Server(8651)│         │                 │
└──────────────────┘         └────────┬────────┘
                                      │
                             ┌────────▼────────┐
                             │      jrag       │
                             │ VectorDB+GraphDB│
                             │ (MCP via stdio) │
                             └─────────────────┘
```

- **jadx-ai-mcp**: Provides the JADX GUI (via noVNC) and an MCP HTTP service for precise decompilation and Android-specific information.
- **opencode**: An AI Agent that invokes jrag and jadx via the MCP protocol.
- **jrag**: A semantic index and call graph built from jadx source code; installed alongside opencode.

## Quick Start

### Dependencies

- Docker + Docker Compose
- An OpenAI-compatible API (DeepSeek, SiliconFlow, OpenAI, etc.)

### Startup

```bash
docker compose up -d --build
```

Upon initial startup, the system will:

1. Download the latest `evil-opencode` binary.
2. Install `jrag-cli` (takes approximately 5–10 minutes).
3. Create a dummy `pom.xml` (if the source code directory is empty).
4. Build the initial index.

### API Configuration

After entering the OpenCode TUI, configure the API using the `/connect` command:

```bash
docker attach opencode
```

Run `/connect` inside the TUI, select your provider, and paste the API Key and Base URL. Credentials are persisted in the `opencode-data` volume, so no re-configuration is needed later.

### Add an APK

```bash
./add_apk.sh /path/to/your_app.apk
```

The script performs the following steps: copies the APK → decompiles it with jadx → adds the source code to `./repos/<apk-name>/` → rebuilds the index. Each APK's source lives in its own subdirectory, so multiple APKs won't overwrite each other even if they share the same package name.

### Install Recommended Skills (Optional)

`install-skills.sh` installs a set of recommended OpenCode Skills for reverse engineering (routing pack + mobile static analysis). Skills extend the AI's domain knowledge without changing the core pipeline.

Run it from the project root on the **host machine** — the script copies skills into the running `opencode` container and persists them via the `opencode-config` volume:

```bash
bash recommend-skills.sh
```

The script will:

1. Locate the running `opencode` container (or start it if stopped)
2. Clone skill repositories on the host
3. Copy skills into `/root/.config/opencode/skills/` inside the container

Installed skills:

- `reverse-engineering` (from [zhaoxuya520/reverse-skill](https://github.com/zhaoxuya520/reverse-skill))
- `mobile-reverse` (from [alvinhayy/Mobile-ReverseSkill](https://github.com/alvinhayy/Mobile-ReverseSkill))

Restart OpenCode to apply:

```bash
docker compose restart opencode
```

Then ask inside the TUI: `What skills are available now?`

> **Note**: `docker compose down -v` will delete the `opencode-config` volume (and all installed skills). Re-run `install-skills.sh` to restore.

### Usage

```bash
docker attach opencode
```

Ask questions directly, for example:

```
What Activities are in this app?
Which key services does com.example.MainActivity call?
```

Use `/mcp list` to check the MCP connection status.

## Optional Configuration

Create a `.env` file to override the following default values (all are **optional**):

```env
# External ports for JADX GUI and MCP services
JADX_GUI_PORT=6080
JADX_MCP_PORT=8651

# jrag embedding model (choose a model from HuggingFace)
SBERT_MODEL=sentence-transformers/all-MiniLM-L6-v2

# jrag embedding device: cpu / cuda / mps
# Set to 'cuda' for NVIDIA GPUs, or 'mps' for Apple devices
SBERT_DEVICE=cpu
```

## Known Pitfalls

### 1. JADX Dual Tokens

JADX uses **two separate sets of tokens**:

| Token | Default Value | Purpose |
|---|---|---|
| Plugin Token | `jadx-plugin-secret-token` | Internal GUI plugin communication (port 8650) |
| MCP Admin Token | `admin-secret-token` | External MCP Server authentication (port 8651) |

OpenCode connects to the MCP Server, so you must use the Admin Token. The format is `Bearer admin-secret-token` (note the space).

The default values are already configured in `init-opencode.sh`. If you customize `JADX_MCP_AUTH_TOKEN`, you must also update the corresponding header in `init-opencode.sh`.

### 2. `jrag increment` does not detect new files

`jrag increment` only updates changes to already indexed files; it **does not scan for newly added files**. You must rebuild the index after adding a new APK.

`add_apk.sh` includes this logic: it first attempts an incremental update; if the file count remains unchanged, it automatically falls back to a full `jrag install`.

### 3. jadx GUI requires manual APK loading

Once the MCP service is running, the tool cannot find anything unless an APK is opened in the JADX GUI. Access `http://<IP>:6080` in your browser and open `/apks/xxx.apk` within the GUI.

### 4. Cross-APK FQN conflicts

Subdirectory isolation resolves path conflicts but not FQN (Fully Qualified Name) conflicts. If two APKs both contain the class `com.example.package.Class`, LadybugDB will still report a `Symbol already exists` error during graph construction.

## Project Structure

```
.
├── docker-compose.yml
├── add_apk.sh              # One-click APK addition
├── install-skills.sh       # Install recommended OpenCode Skills
├── .env                    # Optional configuration
├── opencode/
│   ├── Dockerfile
│   └── init-opencode.sh
├── apks/                   # Place APK files here
├── repos/                  # Decompiled Java source code
│   ├── apk_1/
│   └── apk_2/
└── data/
    └── jrag-index/         # Persistent jrag index
```

## Workflow Recommendations

**Prompt template for AI** (to save tokens):

> Answer directly. Call only the necessary tools—at most 1–2 times. Do not perform extra state verification.

**Analysis Workflow:**

1. Use `jrag search` to locate relevant classes.
2. Use `jrag neighbors` / `callers` to trace the call chain.
3. When precise source code is required, use jadx MCP or directly read files in `/workspace/<apk-name>/`.

**Multi-APK Management**: Each APK's source code lives in its own subdirectory under `/workspace/`. Different APKs won't overwrite each other even if they share the same package name.

## Known Limitations

- The jadx GUI can only load one APK at a time.
- jrag graph queries do not span across APKs.
- The default embedding model has limited understanding of Chinese semantics; using English keywords is recommended, or switch `SBERT_MODEL` to `BAAI/bge-small-zh-v1.5`.
- Initial indexing for large APKs (10k+ classes) takes approximately 1 hour.

## Acknowledgments

This project is an orchestration of the following tools; core functionalities are provided by the upstream projects:

- [evil-opencode](https://github.com/WinMin/evil-opencode)
- [jrag](https://github.com/HumanBean17/jrag)
- [jadx-ai-mcp](https://github.com/xjoker/jadx-ai-mcp)
- [jadx](https://github.com/skylot/jadx)

## License

MIT
