#!/bin/bash
set -e  # 遇到错误立即停止

# ==============================================================================
# 1. 基础环境与源配置
# ==============================================================================
echo ">>> Installing dependencies and configuring repositories..."

# 更新并安装基础工具
apt-get update -y
apt-get install -y --no-install-recommends \
    curl wget git build-essential libssl-dev libffi-dev \
    python3 python3-venv python3-dev python3-pip \
    jq sudo openssh-client openssh-server software-properties-common \
    gnupg lsb-release ca-certificates apt-transport-https \
    locales tzdata fontconfig

# --- Node.js 22 ---
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -

# --- Cloudflared & WARP ---
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | gpg --dearmor | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared jammy main' | tee /etc/apt/sources.list.d/cloudflared.list

curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ jammy main" | tee /etc/apt/sources.list.d/cloudflare-client.list

# --- Microsoft (.NET 6.0) ---
wget https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb

# --- Eclipse Adoptium (JDK 8 Temurin) ---
wget -O - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | tee /usr/share/keyrings/adoptium.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" | tee /etc/apt/sources.list.d/adoptium.list

# ==============================================================================
# 2. 安装软件包
# ==============================================================================
echo ">>> Installing packages..."

apt-get update -y
apt-get install -y --no-install-recommends \
    nodejs \
    cloudflared \
    cloudflare-warp \
    pipx \
    temurin-8-jdk \
    maven \
    dotnet-sdk-6.0 \
    fonts-noto-cjk \
    fonts-noto-cjk-extra \
    fonts-wqy-zenhei \
    fonts-wqy-microhei

# ==============================================================================
# 3. 系统配置 (Locale, Timezone, Fonts)
# ==============================================================================
echo ">>> Configuring system (Timezone, Locale, Fonts)..."

# 设置时区
ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 生成 Locale
locale-gen zh_CN.UTF-8

# 刷新字体缓存
fc-cache -fv

# 确保 pipx 路径 (为 root 预备，虽然后续主要用 docker 用户)
pipx ensurepath

# ==============================================================================
# 4. 清理垃圾
# ==============================================================================
echo ">>> Cleaning up..."
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/*
