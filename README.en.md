# apks2opencode

English | [中文](README.md)

A Docker-based APK reverse engineering environment. Combines JADX, jrag, and OpenCode into a pipeline that lets AI understand decompiled code and trace call chains.

**Highlights:**

- **One-command setup**: `docker compose up` brings up the whole stack, no manual installation
- **Natural language analysis**: Skip manual code reading — just ask "where's the payment logic" or "who calls this method"
- **Semantic search + call graph**: jrag provides vector retrieval and graph queries, far more efficient than grep
- **Fully local indexing**: Code never leaves your machine, index persists and supports incremental updates

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
                             │ Vector + Graph  │
                             │ (MCP via stdio) │
                             └─────────────────┘
```

- **jadx-ai-mcp**: JADX GUI (noVNC) + MCP HTTP service for precise decompilation and Android-specific info
- **opencode**: AI Agent that calls jrag and jadx via MCP
- **jrag**: Semantic index and call graph built from jadx source, installed alongside opencode

## Quick Start

### Requirements

- Docker + Docker Compose
- An OpenAI-compatible API (DeepSeek, SiliconFlow, OpenAI, etc.)

### Launch

```bash
docker compose up -d --build
```

On first launch it will:
1. Download the latest evil-opencode binary
2. Install jrag-cli (~5-10 minutes)
3. Create a dummy pom.xml if the source directory is empty
4. Build the initial index

### Configure API

Enter the OpenCode TUI and use the `/connect` command:

```bash
docker attach opencode
```

Run `/connect` inside the TUI, select your provider, and paste your API key and base URL. Credentials persist in the `opencode-data` volume.

### Add an APK

```bash
./add_apk.sh /path/to/your_app.apk
```

The script handles: copy APK → jadx decompile → merge source into `./repos` → rebuild index.

### Usage

```bash
docker attach opencode
```

Ask directly, for example:

```
What Activities does this app have?
What key services does com.example.MainActivity call?
```

Use `/mcp list` to check MCP connection status.

## Optional Configuration

Create a `.env` file to override the following defaults. **All optional**:

```env
# Ports for JADX GUI and MCP service
JADX_GUI_PORT=6080
JADX_MCP_PORT=8651

# jrag embedding device: cpu / cuda / mps
# Use cuda for NVIDIA GPUs, mps for Apple devices
SBERT_DEVICE=cpu
```

## Known Issues

### 1. JADX dual tokens

JADX has **two separate tokens**:

| Token | Default | Purpose |
|---|---|---|
| Plugin Token | `jadx-plugin-secret-token` | GUI plugin internal comms (8650) |
| MCP Admin Token | `admin-secret-token` | MCP Server external auth (8651) |

OpenCode connects to the MCP Server and must use the Admin Token in the format `Bearer admin-secret-token` (note the space).

`init-opencode.sh` already has the default configured. If you customize `JADX_MCP_AUTH_TOKEN`, update the header in `init-opencode.sh` accordingly.

### 2. jrag increment doesn't detect new files

`jrag increment` only updates changes to already-indexed files — it **does not scan for new files**. You must rebuild the index after adding a new APK.

`add_apk.sh` handles this: it tries increment first, and if the file count doesn't change, falls back to a full `jrag install`.

### 3. JADX GUI needs manual APK loading

After the MCP service is up, if no APK is loaded in the JADX GUI, tools return nothing. Open `http://<IP>:6080` and load `/apks/xxx.apk` in the GUI.

## Project Structure

```
.
├── docker-compose.yml
├── add_apk.sh              # One-command APK import
├── .env                    # Optional config
├── opencode/
│   ├── Dockerfile
│   └── init-opencode.sh
├── apks/                   # Place APK files here
├── repos/                  # Decompiled Java source
└── data/
    └── jrag-index/         # jrag index persistence
```

## Workflow Tips

**Prompt template for AI** (saves tokens):

> Answer directly. Call at most 1-2 tools. No extra state verification.

**Analysis flow**:

1. `jrag search` to locate relevant classes
2. `jrag neighbors` / `callers` to trace call chains
3. Use jadx MCP for precise source, or read files under `/workspace` directly

**Multi-APK management**: Sources from different APKs merge into the `/workspace` root. Different package names won't conflict.

## Known Limitations

- JADX GUI can only load one APK at a time
- jrag graph queries don't span across APKs
- Default embedding model has limited Chinese semantic understanding — prefer English keywords
- Large APKs (10k+ classes) take ~1 hour for initial indexing

## Credits

This project is an orchestration of the following tools. Core functionality is provided upstream:

- [evil-opencode](https://github.com/WinMin/evil-opencode)
- [jrag](https://github.com/HumanBean17/jrag)
- [jadx-ai-mcp](https://github.com/xjoker/jadx-ai-mcp)
- [jadx](https://github.com/skylot/jadx)

## License

MIT
