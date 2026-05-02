#!/bin/bash
set -e

# ==============================================================================
# Lite Version - 精简启动脚本
# ==============================================================================

RUNNER_DIR="/home/docker/actions-runner"
GITHUB_URL_BASE="https://github.com"
API_URL_BASE="https://api.github.com"

# Navigate to runner directory
cd "${RUNNER_DIR}" || { echo "Error: Runner directory not found."; exit 1; }

# ==============================================================================
# 1. Token Management / 令牌管理
# ==============================================================================

if [[ "${REPO}" == *"/"* ]]; then
    CONTEXT_TYPE="repo"
    TARGET_URL="${GITHUB_URL_BASE}/${REPO}"
    API_ENDPOINT="${API_URL_BASE}/repos/${REPO}/actions/runners/registration-token"
else
    CONTEXT_TYPE="org"
    TARGET_URL="${GITHUB_URL_BASE}/${REPO}"
    API_ENDPOINT="${API_URL_BASE}/orgs/${REPO}/actions/runners/registration-token"
fi

if [[ -n "${ACCESS_TOKEN}" && -z "${REGISTRATION_TOKEN}" ]]; then
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
fi

if [[ -z "${REGISTRATION_TOKEN}" ]]; then
    echo "!!! Error: No REGISTRATION_TOKEN or ACCESS_TOKEN provided."
    exit 1
fi

# ==============================================================================
# 2. Runner Registration / 注册运行器
# ==============================================================================

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
    echo "!!! Fatal Error: Failed to register runner after multiple attempts."
    exit 1
fi

# ==============================================================================
# 3. Cleanup Trap / 清理钩子
# ==============================================================================

deregister_runner() {
    ./config.sh remove --unattended --token "${REGISTRATION_TOKEN}" > /dev/null 2>&1
}

trap 'deregister_runner; exit 130' INT
trap 'deregister_runner; exit 143' TERM

# ==============================================================================
# 4. Execution / 启动运行器
# ==============================================================================

echo ">>> Starting GitHub Actions Runner..."
./run.sh
