# Self-hosted GitHub Actions Runner (Repo & Org Supported)

[中文文档](./README_CN.md)

A powerful, self-hosted GitHub Actions Runner image that **seamlessly supports both Organization-level and Repository-level registration**.

Designed for modularity, you can easily customize the build environment or add runtime commands by modifying the provided scripts.

## ✨ Key Features

- **Dual Mode Support**: Automatically detects `REPO` format to switch between **Organization** or **Repository** registration flows.
- **JIT Mode (Recommended)**: Uses Just-In-Time runner configuration with minimal permissions via Fine-Grained Tokens. No long-lived registration tokens needed.
- **Full-Stack Environment**:
  - Node.js 22, Java 8 (Temurin), .NET 6.0, Python 3 + Pipx
  - Tools: Maven, Git, PM2, EdgeOne/Vercel CLI
- **Security First**: Sensitive tokens are stripped from the environment before execution; Runs as non-root user.

## 🚀 Quick Start

### Scenario A: JIT Mode (Recommended)

Uses Fine-Grained Token with minimal permissions. Each task gets a fresh JIT config and the runner self-deregisters after completion.

**Token Setup**: Create a Fine-Grained Personal Access Token with the following permission:
- **Organization level**: `Self-hosted runners` → `Read and Write`
- **Repository level**: `Actions` → `Read and Write`

**Find your Runner Group ID**:
```bash
# For organization runners
curl -s -H "Authorization: Bearer YOUR_TOKEN" \
  https://api.github.com/orgs/ORG_NAME/actions/runners/groups | jq '.runner_groups[].id'

# For repository runners (group ID is usually 1)
curl -s -H "Authorization: Bearer YOUR_TOKEN" \
  https://api.github.com/repos/OWNER/REPO/actions/runners/groups | jq '.runner_groups[].id'
```

**Run**:
```bash
docker run -d \
  --name jit-runner \
  -e REPO="My-Company-Org" \
  -e ACCESS_TOKEN="github_pat_XXXX" \
  -e USE_JIT="true" \
  -e RUNNER_GROUP_ID="1" \
  my-runner-image
```

### Scenario B: Traditional Mode

Uses Classic PAT with broader permissions (`repo` or `admin:org` scope).

```bash
# Repository Runner
docker run -d \
  --name repo-runner \
  -e REPO="my-user/my-cool-repo" \
  -e ACCESS_TOKEN="ghp_YOUR_PAT..." \
  my-runner-image

# Organization Runner
docker run -d \
  --name org-runner \
  -e REPO="My-Company-Org" \
  -e ACCESS_TOKEN="ghp_YOUR_PAT..." \
  my-runner-image
```

> **About ACCESS_TOKEN (PAT)**:
> - **JIT Mode**: Use Fine-Grained Token with `Self-hosted runners` permission. Narrowest scope, most secure.
> - **Traditional Mode**: Use Classic PAT with `repo` or `admin:org` scope. The script auto-fetches a temporary registration token.
> - If you must use a static `REGISTRATION_TOKEN`, be aware it expires quickly (especially for Orgs), causing issues on container restarts.

## ⚙️ Environment Variables

| Variable | Required | Description |
| :--- | :---: | :--- |
| `REPO` | ✅ | **Core Variable**. If it contains `/`, it's a Repo. If not, it's an Org. |
| `USE_JIT` | ❌ | Set to `true` to enable JIT mode (recommended). |
| `ACCESS_TOKEN` | ✅* | GitHub PAT (Classic) or Fine-Grained Token for auto-registration. |
| `RUNNER_GROUP_ID` | JIT | **JIT only**. Runner group ID to join. |
| `REGISTRATION_TOKEN`| ❌ | Manual token. Required if PAT is missing (Use with caution for Orgs). |
| `NAME` | ❌ | Runner name (defaults to Container ID). |

> \* Required when `REGISTRATION_TOKEN` is not provided.

### JIT Mode vs Traditional Mode

| | JIT Mode | Traditional Mode |
|---|---|---|
| Token Type | Fine-Grained PAT | Classic PAT |
| Required Permission | `Self-hosted runners` (Read/Write) | `repo` or `admin:org` |
| Registration | JIT API → `run.sh --jitconfig` | `config.sh` → `run.sh` |
| Token Lifetime | One-time use per task | Long-lived registration |
| Runner Lifecycle | Ephemeral (self-deregisters) | Persistent registration |
| Security | ✅ Minimal permissions | ⚠️ Broader permissions |

## 🛠️ Customization Guide

This image separates logic to make customization easy:

### 1. Modify Installed Packages (Build-time) -> `build.sh`
If you need to **permanently install** software (e.g., `ffmpeg`, `go`, or global `npm` packages), modify `build.sh`.
- **Why**: Keeps the `Dockerfile` clean and leverages Docker caching.
- **Where**: Add your commands in the `Package Installation` or `User Tools` sections.

### 2. Add Extra Commands (Run-time) -> `start.sh`
If you need to run specific services **when the container starts** (e.g., starting a database, mounting files, running FRPC, or background tasks), modify `start.sh`.
- **Where**: Add your commands **before** the `Starting Actions Runner` section at the end of the file.
- **Example**:
  ```bash
  # Add before section 5 in start.sh
  echo ">>> Starting extra services..."
  pm2 start /path/to/my-script.js
  service nginx start
  ```

## ⚠️ Security Note

To prevent malicious workflows from stealing your credentials, `start.sh` uses an `env -u` strategy:
- `ACCESS_TOKEN` and `REGISTRATION_TOKEN` are removed from the environment variables **before** the runner process starts.
- This means you **cannot** access these values via `env.ACCESS_TOKEN` inside your GitHub Actions steps.
- In JIT mode, the token is also removed before each task execution.

## License

MIT
