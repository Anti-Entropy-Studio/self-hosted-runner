#!/bin/bash
set -e

# ==============================================================================
# Configuration & Context Setup / 配置与上下文设置
# ==============================================================================
RUNNER_DIR="/home/docker/actions-runner"
GITHUB_URL_BASE="https://github.com"
API_URL_BASE="https://api.github.com"

# Define a custom logging function to filter messages
# $1: message to log
# $2: flag indicating if the log is specifically related to 7860 (true/false)
log_message() {
  local msg="$1"
  local is_7860_related="${2:-false}"

  # Check if the filtering conditions are met: SPACE_ID must be set and HFHF_PACE must be 'true'
  if [[ -n "$SPACE_ID" && "$HFHF_PACE" == "true" ]]; then
    # Conditions met: Only log if it's 7860-related (message contains "7860" or flag is true)
    if [ "$is_7860_related" = "true" ] || [[ "$msg" == *7860* ]]; then
      echo "$msg"
    fi
  else
    # Conditions NOT met: Suppress all logs by doing nothing.
    : # Do nothing
  fi
}

# Navigate to runner directory
log_message "Error: Runner directory not found." false # Original: echo "Error: Runner directory not found."; exit 1; 
cd "${RUNNER_DIR}" || { log_message "Error: Runner directory not found." false; exit 1; } # Original: cd "${RUNNER_DIR}" || { echo "Error: Runner directory not found."; exit 1; }

# ==============================================================================
# 1. Token Management Strategy / 令牌管理策略
# ==============================================================================

# Check if we are in Repo mode or Org mode based on the slash '/'
# 判断是仓库模式还是组织模式
if [[ "${REPO}" == *"/"* ]]; then
    CONTEXT_TYPE="repo"
    TARGET_URL="${GITHUB_URL_BASE}/${REPO}"
    API_ENDPOINT="${API_URL_BASE}/repos/${REPO}/actions/runners/registration-token"
    log_message ">>> Context: Repository (${REPO})" false # Original: echo ">>> Context: Repository (${REPO})"
else
    CONTEXT_TYPE="org"
    TARGET_URL="${GITHUB_URL_BASE}/${REPO}"
    API_ENDPOINT="${API_URL_BASE}/orgs/${REPO}/actions/runners/registration-token"
    log_message ">>> Context: Organization (${REPO})" false # Original: echo ">>> Context: Organization (${REPO})"
fi

# ------------------------------------------------------------------------------
# Strategy A: Dynamic Exchange (PAT -> Registration Token)
# 策略 A: 动态交换 (使用 PAT 获取注册令牌)
# ------------------------------------------------------------------------------
if [[ -n "${ACCESS_TOKEN}" && -z "${REGISTRATION_TOKEN}" ]]; then
    log_message ">>> Detected PAT (ACCESS_TOKEN). Requesting ephemeral Registration Token..." false # Original: echo ">>> Detected PAT (ACCESS_TOKEN). Requesting ephemeral Registration Token..."
    
    RESPONSE=$(curl -s -X POST \
        -H "Authorization: token ${ACCESS_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        "${API_ENDPOINT}")
    
    FETCHED_TOKEN=$(echo "${RESPONSE}" | jq -r '.token')

    if [[ "${FETCHED_TOKEN}" == "null" || -z "${FETCHED_TOKEN}" ]]; then
        log_message "!!! Fatal Error: Failed to exchange PAT for Registration Token." false # Original: echo "!!! Fatal Error: Failed to exchange PAT for Registration Token."
        log_message "API Response: ${RESPONSE}" false # Original: echo "API Response: ${RESPONSE}"
        exit 1
    fi

    REGISTRATION_TOKEN="${FETCHED_TOKEN}"
    log_message "√ Successfully acquired Registration Token." false # Original: echo "√ Successfully acquired Registration Token."

# ------------------------------------------------------------------------------
# Strategy B: Static Token Warning
# 策略 B: 静态令牌警告 (针对组织级)
# ------------------------------------------------------------------------------
elif [[ -n "${REGISTRATION_TOKEN}" && "${CONTEXT_TYPE}" == "org" ]]; then
    log_message "========================================================================" false # Original: echo "========================================================================"
    log_message "!!! WARNING: Organization Registration Detected with Static Token !!!" false # Original: echo "!!! WARNING: Organization Registration Detected with Static Token !!!"
    log_message "========================================================================" false # Original: echo "========================================================================"
    log_message "You are using a static REGISTRATION_TOKEN for an Organization." false # Original: echo "You are using a static REGISTRATION_TOKEN for an Organization."
    log_message "These tokens have a short lifespan (usually 1 hour)." false # Original: echo "These tokens have a short lifespan (usually 1 hour)."
    log_message "If this container restarts after the token expires, registration will fail" false # Original: echo "If this container restarts after the token expires, registration will fail"
    log_message "with a 404 error." false # Original: echo "with a 404 error."
    log_message "" false # Original: echo ""
    log_message "Recommended: Use ACCESS_TOKEN (PAT) for automatic token generation." false # Original: echo "Recommended: Use ACCESS_TOKEN (PAT) for automatic token generation."
    log_message "========================================================================" false # Original: echo "========================================================================"
    sleep 3 # Pause to let user read
fi

# Validation
if [[ -z "${REGISTRATION_TOKEN}" ]]; then
    log_message "!!! Error: No REGISTRATION_TOKEN or ACCESS_TOKEN provided." false # Original: echo "!!! Error: No REGISTRATION_TOKEN or ACCESS_TOKEN provided."
    exit 1
fi

# ==============================================================================
# 2. Runner Registration / 注册运行器
# ==============================================================================

# Retry configuration
MAX_ATTEMPTS=5
CURRENT_ATTEMPT=0

log_message ">>> Starting Runner registration process..." false # Original: echo ">>> Starting Runner registration process..."

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
        log_message "√ Runner successfully configured." false # Original: echo "√ Runner successfully configured."
        break
    else
        log_message "× Registration failed (Attempt ${CURRENT_ATTEMPT}/${MAX_ATTEMPTS}). Retrying in 5s..." false # Original: echo "× Registration failed (Attempt ${CURRENT_ATTEMPT}/${MAX_ATTEMPTS}). Retrying in 5s..."
        sleep 5
    fi
done

# If loop finished without success (config.sh creates .runner file on success)
if [ ! -f .runner ]; then
    log_message "!!! Fatal Error: Failed to register runner after multiple attempts." false # Original: echo "!!! Fatal Error: Failed to register runner after multiple attempts."
    exit 1
fi

# ==============================================================================
# 3. Cleanup Trap / 清理钩子
# ==============================================================================
deregister_runner() {
    log_message ">>> Signal received. Removing runner..." false # Original: echo ">>> Signal received. Removing runner..."
    # Attempt to remove runner using the token we have
    ./config.sh remove --unattended --token "${REGISTRATION_TOKEN}"
}

# Trap SIGINT and SIGTERM to clean up nicely
trap 'deregister_runner; exit 130' INT
trap 'deregister_runner; exit 143' TERM

# ==============================================================================
# 4. SSH Services / SSH 服务配置
# ==============================================================================
log_message ">>> Configuring SSH server..." false # Original: echo ">>> Configuring SSH server..."

SSH_DIR="/home/docker/.ssh"
mkdir -p "${SSH_DIR}" && chmod 700 "${SSH_DIR}"

# Import keys from GitHub if specified
if [ -n "${GITHUB_SSH_USER}" ]; then
    log_message "Fetching keys for user: ${GITHUB_SSH_USER}" false # Original: echo "Fetching keys for user: ${GITHUB_SSH_USER}"
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
    log_message ">>> Detected WEB_REPO configuration..." true # Original: echo ">>> Detected WEB_REPO configuration..."
    
    # ---------------------------------------------------------
    # FIX: Robust Parsing Logic for "URL:BRANCH"
    # 修复：更稳健的 "URL:分支" 解析逻辑
    # ---------------------------------------------------------
    
    # Attempt to strip the last colon and everything after it
    # 尝试剥离最后一个冒号及之后的内容
    POTENTIAL_URL="${WEB_REPO%:*}"
    
    # Check if we accidentally stripped the protocol (e.g., https:// -> https)
    # 检查是否意外剥离了协议部分 (例如把 https:// 切成了 https)
    if [ "$POTENTIAL_URL" == "https" ] || [ "$POTENTIAL_URL" == "http" ]; then
        # If yes, it means there was no branch specified
        # 如果是，说明用户没有指定分支，刚才切到协议头了
        REPO_URL="$WEB_REPO"
        REPO_BRANCH="main"
    else
        # If no, the split was valid.
        # 否则，分割是有效的
        REPO_URL="$POTENTIAL_URL"
        REPO_BRANCH="${WEB_REPO##*:}"
    fi

    TARGET_DIR="/home/docker/web_app"

    # Clean old directory if exists
    log_message "Cleaning up existing directory: $TARGET_DIR" true # Original: echo "Cleaning up existing directory: $TARGET_DIR"
    rm -rf "$TARGET_DIR"

    # Clone Repository
    log_message "Cloning $REPO_URL (Branch: $REPO_BRANCH)..." true # Original: echo "Cloning $REPO_URL (Branch: $REPO_BRANCH)..."
    
    # Using '|| true' to prevent container exit on clone failure
    # 使用 '|| true' 防止克隆失败导致容器退出
    git clone -b "$REPO_BRANCH" "$REPO_URL" "$TARGET_DIR" || log_message "!!! Clone Failed" true # Original: git clone -b "$REPO_BRANCH" "$REPO_URL" "$TARGET_DIR" || echo "!!! Clone Failed"

    # Start Server if directory exists
    if [ -d "$TARGET_DIR" ]; then
        log_message "√ Clone successful. Starting HTTP server on port 7860..." true # Original: echo "√ Clone successful. Starting HTTP server on port 7860..."
        pm2 start "python3 -m http.server 7860 --directory $TARGET_DIR" --name "web-7860"
    else
        log_message "!!! Directory not found. Skipping web server startup." true # Original: echo "!!! Directory not found. Skipping web server startup."
    fi
else
    log_message ">>> No WEB_REPO environment variable set. Skipping 7860 service." true # Original: echo ">>> No WEB_REPO environment variable set. Skipping 7860 service."
fi

# ==============================================================================
# 6. Execution / 启动运行
# ==============================================================================
log_message ">>> Starting Actions Runner..." false # Original: echo ">>> Starting Actions Runner..."
log_message ">>> Security Note: Tokens are stripped from the runner process environment." false # Original: echo ">>> Security Note: Tokens are stripped from the runner process environment."

# Start the runner in the background
# CRITICAL: We use 'env -u' to prevent the runner job from reading the tokens
# 关键：使用 env -u 启动，确保 Job 运行时无法读取 REGISTRATION_TOKEN 和 ACCESS_TOKEN
env -u REGISTRATION_TOKEN -u ACCESS_TOKEN ./run.sh &

# Capture the process ID
RUNNER_PID=$!

# Wait for the process to finish
wait $RUNNER_PID
