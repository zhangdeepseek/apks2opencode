# apks2opencode

English | [中文](README.zh.md)

A Docker-based environment for APK reverse engineering and analysis. It integrates JADX (decompilation), jrag (semantic indexing), and the OpenCode AI assistant into a unified pipeline, enabling the AI ​​to understand decompiled code and trace call chains. **Advantages:**

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
                             ┌────────▼───────────┐
                             │      jrag          │
                             │Vector DB + Graph DB│
                             │ (MCP via stdio)    │
                             └────────────────────┘
```

- **jadx-ai-mcp**: Provides the JADX GUI (via noVNC) and an MCP HTTP service for precise decompilation and Android-specific information.
- **opencode**: An AI Agent that invokes jrag and jadx via the MCP protocol.
- **jrag**: A semantic index and call graph built upon jadx source code; installed alongside opencode.

## Quick Start

### Dependencies

- Docker + Docker Compose
- An OpenAI-compatible API (DeepSeek, SiliconFlow, OpenAI, etc.)

### Startup

```bash
docker compose up -d --build
```

Upon initial startup, the system will:
1. Download the latest binary for evil-opencode.
2. Install jrag-cli (takes approximately 5–10 minutes).
3. Create a dummy `pom.xml` (if the source code directory is empty).
4. Build the initial index.

### API Configuration

After entering the OpenCode TUI, configure the API using the `/connect` command:

```bash
docker attach opencode
```

Execute within the TUI. Run `/connect`, select your provider, and paste the API Key and Base URL. Credentials are persisted in the `opencode-data` volume, so no re-configuration is needed later.

### Add an APK

```bash
./add_apk.sh /path/to/your_app.apk
```

The script performs the following steps: copies the APK → decompiles it with jadx → adds the source code to `./repos/Your_APK_Name` → rebuilds the index.

### Usage

```bash
docker attach opencode
```

Ask questions directly, for example:

```
Which Activities are in this app?
What key services does com.example.MainActivity call?
```

Run `/mcp list` to check the MCP connection status.

## Optional Configuration

Create a `.env` file to override the following default values ​​(all are **optional**):

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

## Known Issues / Pitfalls

### 1. JADX Dual Tokens

JADX uses **two separate sets of tokens**:

| Token | Default Value | Purpose |
|---|---|---|
| Plugin Token | `jadx-plugin-secret-token` | Internal GUI plugin communication (port 8650) |
| MCP Admin Token | `admin-secret-token` | External MCP Server authentication (port 8651) |

OpenCode connects to the MCP Server, so you must use the Admin Token. The format is `Bearer admin-secret-token` (note the space).

The default values ​​are already configured in `init-opencode.sh`. If you customize `JADX_MCP_AUTH_TOKEN`, you must also update the corresponding header in `init-opencode.sh`.

### 2. `jrag increment` does not detect new files

`jrag increment` only updates changes to already indexed files; it **does not scan for newly added files**. You must rebuild the index after adding a new APK.

`add_apk.sh` includes this logic: it first attempts an incremental update; if the file count remains unchanged, it automatically falls back to a full `jrag install`.

### 3. jadx GUI requires manual APK loading

Once the MCP service is running, the tool cannot find anything unless an APK is opened in the JADX GUI. Access `http://<IP>:6080` in your browser and open `/apks/xxx.apk` within the GUI.

### 4. Cross-APK FQN conflicts

Subdirectory isolation resolves path conflicts but not FQN (Fully Qualified Name) conflicts. If two APKs both contain the class `com.example.package.class`, LadybugDB will still report a "Symbol already exists" error during graph construction.

## Project Structure

```
.
├── docker-compose.yml
├── add_apk.sh              # One-click APK addition
├── .env                    # Optional configuration
├── opencode/
│   ├── Dockerfile
│   └── init-opencode.sh
├── apks/                   # Place APK files here
├── repos/                  # Decompiled Java source code
│   ├── apk_1/
│   └── apk_2/
└── data/
└── jrag-index/         # jrag index persistence
```

## Recommended Workflow

**Prompt template for AI** (to save tokens):

> Answer directly. Call only the necessary tools, at most 1–2 times. Do not perform extra state verification. **Analysis Workflow**:

1. Use `jrag search` to locate relevant classes.
2. Use `jrag neighbors` / `callers` to trace the call chain.
3. When precise source code is required, use jadx MCP or directly read files in `/workspace/Your_APK_Name`.

**Multi-APK Management**:

Source code from different APKs is merged into the `/workspace/Your_APK_Name` root directory; there are no conflicts provided package names differ.

## Known Limitations

- The jadx GUI can only load one APK at a time.
- jrag graph queries do not span across APKs.
- The default embedding model has limited understanding of Chinese semantics; using English keywords is recommended.
- Initial indexing for large APKs (10k+ classes) takes approximately 1 hour.

## Acknowledgments

This project is an orchestration of the following tools; core functionalities are provided by the upstream projects:

- [evil-opencode](https://github.com/WinMin/evil-opencode)
- [jrag](https://github.com/HumanBean17/jrag)
- [jadx-ai-mcp](https://github.com/xjoker/jadx-ai-mcp)
- [jadx](https://github.com/skylot/jadx)

## License

MIT
