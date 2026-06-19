#!/bin/bash
set -e

# ==============================================================================
# Lite Version - 只安装最基本的依赖
# ==============================================================================

echo ">>> Installing base dependencies..."

apt-get update -y
apt-get install -y --no-install-recommends \
    curl wget git unzip build-essential \
    python3 python3-pip python3-venv \
    jq sudo \
    ca-certificates apt-transport-https \
    locales tzdata

# --- Node.js 22 ---
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y --no-install-recommends nodejs

# ==============================================================================
# System Configuration
# ==============================================================================

echo ">>> Configuring system..."

ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
locale-gen zh_CN.UTF-8

# ==============================================================================
# Cleanup
# ==============================================================================

echo ">>> Cleaning up..."
apt-get clean
rm -rf /var/lib/apt/lists/*
