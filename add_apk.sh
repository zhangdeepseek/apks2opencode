#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APKS_DIR="$SCRIPT_DIR/apks"
REPOS_DIR="$SCRIPT_DIR/repos"

usage() {
    echo "用法: $0 <APK文件路径> [--force]"
    echo "示例: $0 /path/to/app.apk"
    exit 1
}

if [ $# -lt 1 ]; then
    usage
fi

APK_PATH="$1"
FORCE=false
shift
while [ $# -gt 0 ]; do
    case "$1" in
        --force) FORCE=true ;;
        *) echo "未知选项: $1"; usage ;;
    esac
    shift
done

if [ ! -f "$APK_PATH" ]; then
    echo -e "${RED}错误: 文件 '$APK_PATH' 不存在${NC}"
    exit 1
fi

APK_PATH=$(realpath "$APK_PATH")
APK_BASENAME=$(basename "$APK_PATH" .apk)

mkdir -p "$APKS_DIR"
APK_IN_APKS="$APKS_DIR/$APK_BASENAME.apk"
if [ "$APK_PATH" != "$APK_IN_APKS" ]; then
    echo -e "${BLUE}📦 复制 APK 到 $APKS_DIR ...${NC}"
    cp "$APK_PATH" "$APK_IN_APKS"
fi

if ! docker compose ps --services --filter "status=running" 2>/dev/null | grep -q "jadx-ai-mcp"; then
    echo -e "${RED}错误: jadx-ai-mcp 容器未运行${NC}"
    exit 1
fi
if ! docker compose ps --services --filter "status=running" 2>/dev/null | grep -q "opencode"; then
    echo -e "${RED}错误: opencode 容器未运行${NC}"
    exit 1
fi

JADX_OUT="/apks/${APK_BASENAME}_jadx_output"
JADX_OUT_HOST="$APKS_DIR/${APK_BASENAME}_jadx_output"

if docker compose exec -T jadx-ai-mcp [ -d "$JADX_OUT" ] 2>/dev/null && [ "$FORCE" = false ]; then
    echo -e "${YELLOW}⚠️  反编译输出目录已存在（容器内）: $JADX_OUT${NC}"
    echo -e "${YELLOW}   使用 --force 强制重新反编译${NC}"
else
    echo -e "${BLUE}🔧 反编译 $APK_BASENAME.apk ...${NC}"
    if [ -d "$JADX_OUT_HOST" ]; then
        rm -rf "$JADX_OUT_HOST"
    fi
    docker compose exec -T jadx-ai-mcp bash -c "rm -rf $JADX_OUT && mkdir -p $JADX_OUT && /opt/jadx/bin/jadx /apks/${APK_BASENAME}.apk -d $JADX_OUT --deobf --show-bad-code" || true
    if ! docker compose exec -T jadx-ai-mcp [ -d "$JADX_OUT/sources" ] 2>/dev/null; then
        echo -e "${RED}❌ 反编译失败，未生成 sources 目录${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ 反编译完成${NC}"
fi

# 函数：获取当前索引的文件数
get_files_count() {
    docker compose exec -T opencode jrag meta 2>/dev/null | jq -r '.counts.files // 0' 2>/dev/null || echo 0
}

BEFORE=$(get_files_count)
echo -e "${BLUE}📊 当前索引文件数: $BEFORE${NC}"

# 复制源码到宿主机 repos（挂载到 /workspace）
echo -e "${BLUE}📂 合并源码到 $REPOS_DIR ...${NC}"
cp -r "$JADX_OUT_HOST/sources/"* "$REPOS_DIR/" 2>/dev/null || true
cp -r "$JADX_OUT_HOST/resources/"* "$REPOS_DIR/" 2>/dev/null || true
echo -e "${GREEN}✅ 源码合并完成${NC}"

# 尝试增量更新
echo -e "${BLUE}📊 尝试增量更新索引 ...${NC}"
docker compose exec -T opencode jrag increment || true
AFTER=$(get_files_count)
echo -e "${BLUE}📊 增量后索引文件数: $AFTER${NC}"

if [ "$AFTER" -eq "$BEFORE" ]; then
    echo -e "${YELLOW}⚠️  增量更新未检测到新文件，将执行全量重建（耗时较长）...${NC}"
    docker compose exec -T opencode bash -c "rm -rf /workspace/.java-codebase-rag && jrag install --non-interactive --surface mcp --agent claude-code"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 全量重建完成${NC}"
    else
        echo -e "${RED}❌ 全量重建失败${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✅ 增量更新成功${NC}"
fi

# 显示最终统计
echo -e "${BLUE}📋 最终索引统计:${NC}"
docker compose exec -T opencode jrag meta | jq -r '"[\(.counts.files)] files, [\(.counts.types)] types, [\(.counts.calls)] calls"'

echo -e "${GREEN}🎉 添加 APK 完成！${NC}"
echo -e "${YELLOW}提示: 新 APK 的源码已合并到 /workspace，索引已更新。${NC}"
