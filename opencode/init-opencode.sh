#!/bin/sh
set -e

echo "Checking /workspace for build files..."
cd /workspace

# 如果不存在构建文件，创建 dummy pom.xml
if [ ! -f "pom.xml" ] && [ ! -f "build.gradle" ] && [ ! -f "build.gradle.kts" ] && [ ! -f "build.sbt" ]; then
    echo "No build file found, creating dummy pom.xml to bypass jrag check."
    cat > pom.xml << 'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>dummy</groupId>
    <artifactId>dummy</artifactId>
    <version>1.0</version>
</project>
EOF
fi

echo "Running jrag install..."
cd /workspace
jrag install --non-interactive --surface mcp --agent claude-code

echo "Generating opencode config..."
mkdir -p /root/.config/opencode
cat > /root/.config/opencode/opencode.json <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "mcp": {
    "jrag": {
      "type": "local",
      "command": ["jrag-mcp"],
      "cwd": "/workspace",
      "env": {
        "JAVA_CODEBASE_RAG_SOURCE_ROOT": "/workspace",
        "JAVA_CODEBASE_RAG_INDEX_DIR": "/workspace/.java-codebase-rag"
      },
      "enabled": true
    },
    "jadx": {
      "type": "remote",
      "url": "http://jadx-ai-mcp:8651/mcp",
      "headers": {
        "Authorization": "Bearer admin-secret-token"
      },
      "enabled": true
    }
  }
}
EOF

echo "Starting opencode..."
export OPENAI_API_KEY="${OPENAI_API_KEY}"
export JAVA_CODEBASE_RAG_SOURCE_ROOT=/workspace
export JAVA_CODEBASE_RAG_INDEX_DIR=/workspace/.java-codebase-rag
export OPENAI_BASE_URL="${OPENAI_BASE_URL}"
exec /usr/local/bin/opencode
