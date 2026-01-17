# Self-hosted GitHub Actions Runner (Repo & Org Supported)
[中文文档](./README_CN.md)
A powerful, self-hosted GitHub Actions Runner image that **seamlessly supports both Organization-level and Repository-level registration**.

Designed for modularity, you can easily customize the build environment or add runtime commands by modifying the provided scripts.

## ✨ Key Features

- **Dual Mode Support**: Automatically detects `REPO` format to switch between **Organization** or **Repository** registration flows.
- **Full-Stack Environment**:
  - Node.js 22, Java 8 (Temurin), .NET 6.0, Python 3 + Pipx
  - Tools: Cloudflared, Maven, Git, SSH, PM2, EdgeOne/Vercel CLI
- **Security First**: Sensitive tokens are stripped from the environment before execution; Runs as non-root user.
- **SSH Debugging**: Built-in SSH Server (Port 7450) with auto-import of GitHub public keys.

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

## 🚀 Quick Start

### Scenario A: Repository Runner
For a single specific repository.
**REPO Format**: `username/repo-name` (contains `/`)

```bash
docker run -d \
  --name repo-runner \
  -e REPO="my-user/my-cool-repo" \
  -e ACCESS_TOKEN="ghp_YOUR_PAT..." \
  my-runner-image
```

### Scenario B: Organization Runner
For all repositories within an organization.
**REPO Format**: `org-name` (does NOT contain `/`)

```bash
docker run -d \
  --name org-runner \
  -e REPO="My-Company-Org" \
  -e ACCESS_TOKEN="ghp_YOUR_PAT..." \
  my-runner-image
```

> **About ACCESS_TOKEN (PAT)**:
> It is highly recommended to use a PAT (with `repo` or `admin:org` scope). The script will automatically fetch a temporary registration token.
> If you must use a static `REGISTRATION_TOKEN`, be aware it expires quickly (especially for Orgs), causing issues on container restarts.

## ⚙️ Environment Variables

| Variable | Required | Description |
| :--- | :---: | :--- |
| `REPO` | ✅ | **Core Variable**. If it contains `/`, it's a Repo. If not, it's an Org. |
| `ACCESS_TOKEN` | ❌ | **Recommended**. GitHub PAT for auto-registration. |
| `REGISTRATION_TOKEN`| ❌ | Manual token. Required if PAT is missing (Use with caution for Orgs). |
| `NAME` | ❌ | Runner name (defaults to Container ID). |
| `GITHUB_SSH_USER` | ❌ | If set, downloads the user's public keys from GitHub for SSH access. |

## 🔌 SSH Access

The container exposes port **7450** for SSH.

1. Start with `GITHUB_SSH_USER=your_username`.
2. Connect: `ssh -p 7450 docker@<container-ip>`

## ⚠️ Security Note

To prevent malicious workflows from stealing your credentials, `start.sh` uses an `env -u` strategy:
- `ACCESS_TOKEN` and `REGISTRATION_TOKEN` are removed from the environment variables **before** the runner process starts.
- This means you **cannot** access these values via `env.ACCESS_TOKEN` inside your GitHub Actions steps.

## License

MIT
