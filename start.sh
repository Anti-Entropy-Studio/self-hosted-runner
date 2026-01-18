#!/bin/bash
set -e

# ==============================================================================
# Configuration & Context Setup / 配置与上下文设置
# ==============================================================================
RUNNER_DIR="/home/docker/actions-runner"
GITHUB_URL_BASE="https://github.com"
API_URL_BASE="https://api.github.com"

# Navigate to runner directory
cd "${RUNNER_DIR}" || { echo "Error: Runner directory not found."; exit 1; }

# ==============================================================================
# 1. Token Management Strategy / 令牌管理策略
# ==============================================================================

# Check if we are in Repo mode or Org mode based on the slash '/'
# 判断是仓库模式还是组织模式
if [[ "${REPO}" == *"/"* ]]; then
    CONTEXT_TYPE="repo"
    TARGET_URL="${GITHUB_URL_BASE}/${REPO}"
    API_ENDPOINT="${API_URL_BASE}/repos/${REPO}/actions/runners/registration-token"
    echo ">>> Context: Repository (${REPO})"
else
    CONTEXT_TYPE="org"
    TARGET_URL="${GITHUB_URL_BASE}/${REPO}"
    API_ENDPOINT="${API_URL_BASE}/orgs/${REPO}/actions/runners/registration-token"
    echo ">>> Context: Organization (${REPO})"
fi

# ------------------------------------------------------------------------------
# Strategy A: Dynamic Exchange (PAT -> Registration Token)
# 策略 A: 动态交换 (使用 PAT 获取注册令牌)
# ------------------------------------------------------------------------------
if [[ -n "${ACCESS_TOKEN}" && -z "${REGISTRATION_TOKEN}" ]]; then
    echo ">>> Detected PAT (ACCESS_TOKEN). Requesting ephemeral Registration Token..."
    
    RESPONSE=$(curl -s -X POST \
        -H "Authorization: token ${ACCESS_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        "${API_ENDPOINT}")
    
    FETCHED_TOKEN=$(echo "${RESPONSE}" | jq -r '.token')

    if [[ "${FETCHED_TOKEN}" == "null" || -z "${FETCHED_TOKEN}" ]]; then
        echo "!!! Fatal Error: Failed to exchange PAT for Registration Token."
        echo "API Response: ${RESPONSE}"
        exit 1
    fi

    REGISTRATION_TOKEN="${FETCHED_TOKEN}"
    echo "√ Successfully acquired Registration Token."

# ------------------------------------------------------------------------------
# Strategy B: Static Token Warning
# 策略 B: 静态令牌警告 (针对组织级)
# ------------------------------------------------------------------------------
elif [[ -n "${REGISTRATION_TOKEN}" && "${CONTEXT_TYPE}" == "org" ]]; then
    echo "========================================================================"
    echo "!!! WARNING: Organization Registration Detected with Static Token !!!"
    echo "========================================================================"
    echo "You are using a static REGISTRATION_TOKEN for an Organization."
    echo "These tokens have a short lifespan (usually 1 hour)."
    echo "If this container restarts after the token expires, registration will fail"
    echo "with a 404 error."
    echo ""
    echo "Recommended: Use ACCESS_TOKEN (PAT) for automatic token generation."
    echo "========================================================================"
    sleep 3 # Pause to let user read
fi

# Validation
if [[ -z "${REGISTRATION_TOKEN}" ]]; then
    echo "!!! Error: No REGISTRATION_TOKEN or ACCESS_TOKEN provided."
    exit 1
fi

# ==============================================================================
# 2. Runner Registration / 注册运行器
# ==============================================================================

# Retry configuration
MAX_ATTEMPTS=5
CURRENT_ATTEMPT=0

echo ">>> Starting Runner registration process..."

while [ ${CURRENT_ATTEMPT} -lt ${MAX_ATTEMPTS} ]; do
    CURRENT_ATTEMPT=$((CURRENT_ATTEMPT + 1))
    
    # Configure command
    ./config.sh \
        --url "${TARGET_URL}" \
        --token "${REGISTRATION_TOKEN}" \
        --name "${NAME:-$(hostname)}" \
        --unattended \
        --replace

    # Check exit code
    if [ $? -eq 0 ]; then
        echo "√ Runner successfully configured."
        break
    else
        echo "× Registration failed (Attempt ${CURRENT_ATTEMPT}/${MAX_ATTEMPTS}). Retrying in 5s..."
        sleep 5
    fi
done

# If loop finished without success (config.sh creates .runner file on success)
if [ ! -f .runner ]; then
    echo "!!! Fatal Error: Failed to register runner after multiple attempts."
    exit 1
fi

# ==============================================================================
# 3. Cleanup Trap / 清理钩子
# ==============================================================================
deregister_runner() {
    echo ">>> Signal received. Removing runner..."
    # Attempt to remove runner using the token we have
    ./config.sh remove --unattended --token "${REGISTRATION_TOKEN}"
}

# Trap SIGINT and SIGTERM to clean up nicely
trap 'deregister_runner; exit 130' INT
trap 'deregister_runner; exit 143' TERM

# ==============================================================================
# 4. SSH Services / SSH 服务配置
# ==============================================================================
echo ">>> Configuring SSH server..."

SSH_DIR="/home/docker/.ssh"
mkdir -p "${SSH_DIR}" && chmod 700 "${SSH_DIR}"

# Import keys from GitHub if specified
if [ -n "${GITHUB_SSH_USER}" ]; then
    echo "Fetching keys for user: ${GITHUB_SSH_USER}"
    curl -s "https://github.com/${GITHUB_SSH_USER}.keys" > "${SSH_DIR}/authorized_keys"
    chmod 600 "${SSH_DIR}/authorized_keys"
fi

# Generate host keys
ssh-keygen -A >/dev/null 2>&1 || true
if [ ! -f "${SSH_DIR}/ssh_host_rsa_key" ]; then
    ssh-keygen -t rsa -f "${SSH_DIR}/ssh_host_rsa_key" -N "" -q
fi

# Create custom sshd config
cat <<EOF > /home/docker/sshd_config
Port 7450
HostKey ${SSH_DIR}/ssh_host_rsa_key
PidFile /home/docker/sshd.pid
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

# Start SSHD via PM2
pm2 start "/usr/sbin/sshd -D -f /home/docker/sshd_config" --name "sshd-server"

# ==============================================================================
# 5. Web Service (Optional) / 可选 Web 服务 (Port 7860)
# ==============================================================================
# Checks WEB_REPO env var. Format: "URL:BRANCH" or just "URL"
# 检查 WEB_REPO 环境变量。格式："URL:分支" 或 仅 "URL"

if [ -n "$WEB_REPO" ]; then
    echo ">>> Detected WEB_REPO configuration..."
    
    # Parse URL and Branch
    # 解析 URL 和 分支
    if [[ "$WEB_REPO" == *":"* ]]; then
        REPO_URL="${WEB_REPO%%:*}"    # Left of colon
        REPO_BRANCH="${WEB_REPO##*:}"  # Right of colon
    else
        REPO_URL="$WEB_REPO"
        REPO_BRANCH="main"             # Default branch
    fi

    TARGET_DIR="/home/docker/web_app"

    # Clean old directory if exists
    if [ -d "$TARGET_DIR" ]; then
        echo "Cleaning up existing directory: $TARGET_DIR"
        rm -rf "$TARGET_DIR"
    fi

    # Clone Repository
    echo "Cloning $REPO_URL (Branch: $REPO_BRANCH)..."
    # We use '|| true' to prevent script exit if clone fails, allowing runner to still start
    # 使用 '|| true' 防止克隆失败导致脚本退出，确保 Runner 仍能启动
    git clone -b "$REPO_BRANCH" "$REPO_URL" "$TARGET_DIR" || echo "!!! Clone Failed"

    # Start Server if directory exists
    if [ -d "$TARGET_DIR" ]; then
        echo "√ Clone successful. Starting HTTP server on port 7860..."
        pm2 start "python3 -m http.server 7860 --directory $TARGET_DIR" --name "web-7860"
    else
        echo "!!! Directory not found. Skipping web server startup."
    fi
else
    echo ">>> No WEB_REPO environment variable set. Skipping 7860 service."
fi

# ==============================================================================
# 6. Execution / 启动运行
# ==============================================================================
echo ">>> Starting Actions Runner..."
echo ">>> Security Note: Tokens are stripped from the runner process environment."

# Start the runner in the background
# CRITICAL: We use 'env -u' to prevent the runner job from reading the tokens
# 关键：使用 env -u 启动，确保 Job 运行时无法读取 REGISTRATION_TOKEN 和 ACCESS_TOKEN
env -u REGISTRATION_TOKEN -u ACCESS_TOKEN ./run.sh &

# Capture the process ID
RUNNER_PID=$!

# Wait for the process to finish
wait $RUNNER_PID
