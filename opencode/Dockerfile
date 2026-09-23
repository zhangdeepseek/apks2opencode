# 使用 Debian 作为基础镜像（glibc，兼容性好）
FROM debian:bookworm-slim

# 安装基础工具和 Python
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    python3 \
    python3-pip \
    python3-venv \
    libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

# 从 evil-opencode 发布页下载二进制
RUN LATEST_TAG=$(curl -s https://api.github.com/repos/WinMin/evil-opencode/releases/latest | grep '"tag_name":' | cut -d'"' -f4) && \
    echo "Downloading evil-opencode ${LATEST_TAG}" && \
    curl -L "https://github.com/winmin/evil-opencode/releases/download/${LATEST_TAG}/opencode-linux-x64" -o /usr/local/bin/opencode && \
    chmod +x /usr/local/bin/opencode

# 验证二进制
RUN ls -la /usr/local/bin/opencode && /usr/local/bin/opencode --version || true

# 安装 jrag-cli（Debian 下 lancedb 有预编译 wheel）
RUN pip3 install --break-system-packages ladybug==0.17.1 && \
    pip3 install --break-system-packages jrag-cli

WORKDIR /workspace

COPY init-opencode.sh /init-opencode.sh
RUN chmod +x /init-opencode.sh

ENTRYPOINT ["/bin/sh", "/init-opencode.sh"]
