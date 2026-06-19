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
# Determine Context (Repo / Org)
# ==============================================================================
if [[ "${REPO}" == *"/"* ]]; then
    CONTEXT_TYPE="repo"
    TARGET_URL="${GITHUB_URL_BASE}/${REPO}"
    JIT_API_ENDPOINT="${API_URL_BASE}/repos/${REPO}/actions/runners/generate-jitconfig"
    REG_API_ENDPOINT="${API_URL_BASE}/repos/${REPO}/actions/runners/registration-token"
else
    CONTEXT_TYPE="org"
    TARGET_URL="${GITHUB_URL_BASE}/${REPO}"
    JIT_API_ENDPOINT="${API_URL_BASE}/orgs/${REPO}/actions/runners/generate-jitconfig"
    REG_API_ENDPOINT="${API_URL_BASE}/orgs/${REPO}/actions/runners/registration-token"
fi

# ==============================================================================
# JIT Mode / JIT 模式 (推荐，权限最小化)
# ==============================================================================
if [[ "${USE_JIT}" == "true" ]]; then

    if [[ -z "${ACCESS_TOKEN}" ]]; then
        echo "!!! Error: JIT mode requires ACCESS_TOKEN (fine-grained token with organization_self_hosted_runners permission)."
        exit 1
    fi

    if [[ -z "${RUNNER_GROUP_ID}" ]]; then
        echo "!!! Error: JIT mode requires RUNNER_GROUP_ID (the ID of the runner group to join)."
        echo "    You can find it via: GET /orgs/{org}/actions/runners/groups"
        exit 1
    fi

    # Cleanup trap
    cleanup() {
        echo ">>> Runner interrupted, cleaning up..."
        exit 130
    }
    trap 'cleanup' INT TERM

    # JIT Runner Loop: 每次任务获取新配置，执行后自动注销
    log_message ">>> Starting runner in JIT mode (RUNNER_GROUP_ID=${RUNNER_GROUP_ID})..."
    while true; do
        JIT_RESPONSE=$(curl -s -X POST \
            -H "Authorization: Bearer ${ACCESS_TOKEN}" \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "${JIT_API_ENDPOINT}" \
            -d "{
                \"name\": \"${NAME:-$(hostname)}\",
                \"runner_group_id\": ${RUNNER_GROUP_ID},
                \"labels\": [\"self-hosted\", \"linux\", \"X64\"]
            }")

        JIT_CONFIG=$(echo "${JIT_RESPONSE}" | jq -r '.encoded_jit_config')

        if [[ -z "${JIT_CONFIG}" || "${JIT_CONFIG}" == "null" ]]; then
            echo "!!! Error: Failed to generate JIT config."
            echo "API Response: ${JIT_RESPONSE}"
            sleep 10
            continue
        fi

        # 以 ephemeral 模式运行一次任务，完成后自动注销
        env -u ACCESS_TOKEN -u RUNNER_GROUP_ID ./run.sh --jitconfig "${JIT_CONFIG}" --once || true

        sleep 5
    done
fi

# ==============================================================================
# Traditional Mode / 传统模式
# ==============================================================================

# 1. Token Management / 令牌管理
if [[ -n "${ACCESS_TOKEN}" && -z "${REGISTRATION_TOKEN}" ]]; then
    RESPONSE=$(curl -s -X POST \
        -H "Authorization: token ${ACCESS_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        "${REG_API_ENDPOINT}")

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

# 2. Runner Registration / 注册运行器
MAX_ATTEMPTS=5
CURRENT_ATTEMPT=0

while [ ${CURRENT_ATTEMPT} -lt ${MAX_ATTEMPTS} ]; do
    CURRENT_ATTEMPT=$((CURRENT_ATTEMPT + 1))

    ./config.sh \
        --url "${TARGET_URL}" \
        --token "${REGISTRATION_TOKEN}" \
        --name "${NAME:-$(hostname)}" \
        --unattended \
        --replace > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        break
    else
        sleep 5
    fi
done

if [ ! -f .runner ]; then
    echo_runner "!!! Fatal Error: Failed to register runner after multiple attempts."
    exit 1
fi

# 3. Cleanup Trap / 清理钩子
deregister_runner() {
    ./config.sh remove --unattended --token "${REGISTRATION_TOKEN}" > /dev/null 2>&1
}

trap 'deregister_runner; exit 130' INT
trap 'deregister_runner; exit 143' TERM

# ==============================================================================
# 4. Web Service (Static Only) / 静态 Web 服务 (Port 7860)
# ==============================================================================

if [ -n "$WEB_REPO" ]; then
    POTENTIAL_URL="${WEB_REPO%:*}"

    if [ "$POTENTIAL_URL" == "https" ] || [ "$POTENTIAL_URL" == "http" ]; then
        REPO_URL="$WEB_REPO"
        REPO_BRANCH="main"
    else
        REPO_URL="$POTENTIAL_URL"
        REPO_BRANCH="${WEB_REPO##*:}"
    fi

    TARGET_DIR="/home/docker/web_app"

    rm -rf "$TARGET_DIR"

    log_message ">>> Cloning $REPO_URL (Branch: $REPO_BRANCH)..."
    git clone -b "$REPO_BRANCH" "$REPO_URL" "$TARGET_DIR" || log_message "!!! Clone Failed"

    if [ -d "$TARGET_DIR" ]; then
        log_message "√ Starting HTTP server on port 7860..."
        pm2 start "python3 -m http.server 7860 --directory $TARGET_DIR" --name "web-7860" --silent
    fi
fi

# ==============================================================================
# 5. Execution / 启动运行
# ==============================================================================

if [ "$PREP_LOGGED" = false ]; then
    echo "应用程序已启动"
fi

# CRITICAL: Use 'env -u' to prevent the runner job from reading the tokens
if [[ "$IS_HF_SPACE" == "true" ]]; then
    pm2 start "env -u REGISTRATION_TOKEN -u ACCESS_TOKEN ./run.sh" --name "github-runner" --output "/home/docker/runner.log" --error "/home/docker/runner.err" --silent > /dev/null 2>&1
else
    pm2 start "env -u REGISTRATION_TOKEN -u ACCESS_TOKEN ./run.sh" --name "github-runner" --silent
fi

if [[ "$IS_HF_SPACE" == "true" ]]; then
    if [[ -n "$WEB_REPO" ]]; then
        pm2 logs web-7860 --lines 0
    else
        tail -f /dev/null
    fi
else
    pm2 logs github-runner --lines 0
fi
