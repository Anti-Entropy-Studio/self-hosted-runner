#!/bin/bash
set -e

# ==============================================================================
# Configuration & Context Setup / 配置与上下文设置
# ==============================================================================
RUNNER_DIR="/home/docker/actions-runner"
GITHUB_URL_BASE="https://github.com"
API_URL_BASE="https://api.github.com"

# Track if any preparation logs were shown
PREP_LOGGED=false

# Detect if running in Hugging Face Space
IS_HF_SPACE=false
if [[ -n "${SPACE_ID}" || -n "${HF_SPACE_ID}" ]]; then
    IS_HF_SPACE=true
fi

log_message() {
  local msg="$1"
  if [[ "$IS_HF_SPACE" == "true" ]]; then
    # In HF Space, only show non-runner related logs
    if [[ "$msg" != *"runner"* && "$msg" != *"Token"* ]]; then
        echo "$msg"
        PREP_LOGGED=true
    fi
  else
    echo "$msg"
    PREP_LOGGED=true
  fi
}

# Helper to echo runner-specific info only if not in HF Space
echo_runner() {
    if [[ "$IS_HF_SPACE" == "false" ]]; then
        echo "$@"
    fi
}

# Navigate to runner directory
cd "${RUNNER_DIR}" || { echo_runner "Error: Runner directory not found."; exit 1; }

# ==============================================================================
# 1. Token Management Strategy / 令牌管理策略
# ==============================================================================

# Check if we are in Repo mode or Org mode based on the slash '/'
if [[ "${REPO}" == *"/"* ]]; then
    CONTEXT_TYPE="repo"
    TARGET_URL="${GITHUB_URL_BASE}/${REPO}"
    API_ENDPOINT="${API_URL_BASE}/repos/${REPO}/actions/runners/registration-token"
else
    CONTEXT_TYPE="org"
    TARGET_URL="${GITHUB_URL_BASE}/${REPO}"
    API_ENDPOINT="${API_URL_BASE}/orgs/${REPO}/actions/runners/registration-token"
fi

# Strategy A: Dynamic Exchange (PAT -> Registration Token)
if [[ -n "${ACCESS_TOKEN}" && -z "${REGISTRATION_TOKEN}" ]]; then
    RESPONSE=$(curl -s -X POST \
        -H "Authorization: token ${ACCESS_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        "${API_ENDPOINT}")
    
    FETCHED_TOKEN=$(echo "${RESPONSE}" | jq -r '.token')

    if [[ "${FETCHED_TOKEN}" == "null" || -z "${FETCHED_TOKEN}" ]]; then
        echo_runner "!!! Fatal Error: Failed to exchange PAT for Registration Token."
        echo_runner "API Response: ${RESPONSE}"
        exit 1
    fi

    REGISTRATION_TOKEN="${FETCHED_TOKEN}"
fi

# Validation
if [[ -z "${REGISTRATION_TOKEN}" ]]; then
    echo_runner "!!! Error: No REGISTRATION_TOKEN or ACCESS_TOKEN provided."
    exit 1
fi

# ==============================================================================
# 2. Runner Registration / 注册运行器 (Silent)
# ==============================================================================

# Retry configuration
MAX_ATTEMPTS=5
CURRENT_ATTEMPT=0

while [ ${CURRENT_ATTEMPT} -lt ${MAX_ATTEMPTS} ]; do
    CURRENT_ATTEMPT=$((CURRENT_ATTEMPT + 1))
    
    # Configure command (silenced)
    ./config.sh \
        --url "${TARGET_URL}" \
        --token "${REGISTRATION_TOKEN}" \
        --name "${NAME:-$(hostname)}" \
        --unattended \
        --replace > /dev/null 2>&1

    # Check exit code
    if [ $? -eq 0 ]; then
        break
    else
        sleep 5
    fi
done

# If loop finished without success
if [ ! -f .runner ]; then
    echo_runner "!!! Fatal Error: Failed to register runner after multiple attempts."
    exit 1
fi

# ==============================================================================
# 3. Cleanup Trap / 清理钩子
# ==============================================================================
deregister_runner() {
    # Attempt to remove runner (silenced)
    ./config.sh remove --unattended --token "${REGISTRATION_TOKEN}" > /dev/null 2>&1
}

# Trap SIGINT and SIGTERM to clean up nicely
trap 'deregister_runner; exit 130' INT
trap 'deregister_runner; exit 143' TERM

# ==============================================================================
# 4. Web Service (Static Only) / 静态 Web 服务 (Port 7860)
# ==============================================================================

if [ -n "$WEB_REPO" ]; then
    # Parsing logic for "URL:BRANCH"
    POTENTIAL_URL="${WEB_REPO%:*}"
    
    if [ "$POTENTIAL_URL" == "https" ] || [ "$POTENTIAL_URL" == "http" ]; then
        REPO_URL="$WEB_REPO"
        REPO_BRANCH="main"
    else
        REPO_URL="$POTENTIAL_URL"
        REPO_BRANCH="${WEB_REPO##*:}"
    fi

    TARGET_DIR="/home/docker/web_app"

    # Clean old directory if exists
    rm -rf "$TARGET_DIR"

    # Clone Repository (Visible prep logs)
    log_message ">>> Cloning $REPO_URL (Branch: $REPO_BRANCH)..."
    git clone -b "$REPO_BRANCH" "$REPO_URL" "$TARGET_DIR" || log_message "!!! Clone Failed"

    # Start Server if directory exists
    if [ -d "$TARGET_DIR" ]; then
        log_message "√ Starting HTTP server on port 7860..."
        pm2 start "python3 -m http.server 7860 --directory $TARGET_DIR" --name "web-7860" --silent
    fi
fi

# ==============================================================================
# 5. Execution / 启动运行
# ==============================================================================

# Show default message if no preparation logs were displayed
if [ "$PREP_LOGGED" = false ]; then
    echo "应用程序已启动"
fi

# Start the runner via PM2 (Silent startup)
# CRITICAL: We use 'env -u' to prevent the runner job from reading the tokens
if [[ "$IS_HF_SPACE" == "true" ]]; then
    # Completely silence runner output by redirecting to a file instead of stdout/stderr
    pm2 start "env -u REGISTRATION_TOKEN -u ACCESS_TOKEN ./run.sh" --name "github-runner" --output "/home/docker/runner.log" --error "/home/docker/runner.err" --silent > /dev/null 2>&1
else
    pm2 start "env -u REGISTRATION_TOKEN -u ACCESS_TOKEN ./run.sh" --name "github-runner" --silent
fi

# Keep the process alive and show logs
if [[ "$IS_HF_SPACE" == "true" ]]; then
    if [[ -n "$WEB_REPO" ]]; then
        # Explicitly only show web server logs
        pm2 logs web-7860 --lines 0
    else
        # Just wait indefinitely without showing any PM2 logs
        tail -f /dev/null
    fi
else
    pm2 logs github-runner --lines 0
fi