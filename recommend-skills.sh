#!/usr/bin/env bash
# install-skills.sh — 为 APK 逆向分析流水线安装推荐 Skill
# 在宿主机项目根目录执行，会自动拷进 opencode 容器并持久化
# 使用: bash install-skills.sh
# 支持: macOS / Linux / WSL

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

echo ""
echo "=== 安装推荐 Skill 到 OpenCode 容器 ==="
echo ""

command -v git  >/dev/null 2>&1 || err "宿主机需要 git"
command -v docker >/dev/null 2>&1 || err "需要 docker"

# ---------- 找到或启动 opencode 容器 ----------
CONTAINER_ID="$(docker compose ps -q opencode 2>/dev/null || true)"
if [ -z "$CONTAINER_ID" ]; then
    echo "opencode 容器未运行，尝试启动..."
    docker compose up -d opencode
    sleep 3
    CONTAINER_ID="$(docker compose ps -q opencode 2>/dev/null || true)"
    [ -z "$CONTAINER_ID" ] && err "启动失败，请手动 docker compose up -d"
fi
ok "opencode 容器: ${CONTAINER_ID:0:12}"

SKILLS_DIR="/root/.config/opencode/skills"
docker exec "$CONTAINER_ID" mkdir -p "$SKILLS_DIR"
ok "Skill 目录: $SKILLS_DIR"

# ---------- 1. reverse-skill（路由包）----------
echo ""
echo "[1/2] reverse-skill"
if docker exec "$CONTAINER_ID" test -d "$SKILLS_DIR/reverse-engineering" 2>/dev/null; then
    warn "已存在，跳过"
else
    git clone --depth 1 \
        https://github.com/zhaoxuya520/reverse-skill.git \
        "$TMP_DIR/reverse-skill"
    docker cp "$TMP_DIR/reverse-skill/skills/." "$CONTAINER_ID:$SKILLS_DIR/"
    ok "reverse-skill 已安装"
fi

# ---------- 2. Mobile-ReverseSkill（静态分析）----------
echo ""
echo "[2/2] Mobile-ReverseSkill"
if docker exec "$CONTAINER_ID" test -d "$SKILLS_DIR/mobile-reverse" 2>/dev/null; then
    warn "已存在，跳过"
else
    git clone --depth 1 \
        https://github.com/alvinhayy/Mobile-ReverseSkill.git \
        "$TMP_DIR/Mobile-ReverseSkill"
    docker cp "$TMP_DIR/Mobile-ReverseSkill/.agents/skills/." "$CONTAINER_ID:$SKILLS_DIR/"
    ok "Mobile-ReverseSkill 已安装"
fi

# ---------- 验证 ----------
echo ""
echo "=== 安装完成 ==="
echo ""
echo "已安装的 Skill:"
docker exec "$CONTAINER_ID" ls "$SKILLS_DIR"
echo ""
echo "重启 OpenCode 后生效："
echo "  docker compose restart opencode"
echo ""
echo "验证方式：进入 TUI 后问「现在有哪些可用的 skill？」"
echo ""
