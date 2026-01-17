# Self-hosted GitHub Actions Runner (Repo & Org Supported)

这是一个功能强大的 GitHub Actions 自托管 Runner 镜像，**完美支持组织级 (Organization) 和仓库级 (Repository) 两种注册模式**。

镜像设计高度模块化，你可以轻松地通过修改脚本来定制构建环境或添加启动命令。

## ✨ 核心特性

- **双模式支持**: 智能识别 `REPO` 变量，自动适配 **组织级** 或 **仓库级** 注册流程。
- **预装全能环境**:
  - Node.js 22, Java 8 (Temurin), .NET 6.0, Python 3 + Pipx
  - 常用工具: Cloudflared, Maven, Git, SSH, PM2, EdgeOne/Vercel CLI
- **安全优先**: 启动时自动剥离敏感 Token，防止 Job 读取；非 Root 用户运行。
- **SSH 调试**: 内置 SSH 服务 (端口 7450)，支持 GitHub 公钥自动导入。

## 🛠️ 自定义与扩展指南

本镜像将配置逻辑分离，方便你根据需求进行修改：

### 1. 修改安装包 (构建时) -> `build.sh`
如果你需要**永久安装**某个软件（如 `ffmpeg`, `go`, 或其他 `npm` 全局包），请修改 `build.sh`。
- **作用**: 保持 `Dockerfile` 整洁，利用 Docker 缓存。
- **位置**: 在 `Package Installation` 或 `User Tools` 区域添加命令。

### 2. 添加额外运行命令 (运行时) -> `start.sh`
如果你需要在**容器启动时**运行某些服务（如启动数据库、挂载文件、运行 FRPC 或其他后台进程），请修改 `start.sh`。
- **位置**: 请务必在文件末尾的 `Starting Actions Runner` 部分**之前**添加代码。
- **示例**:
  ```bash
  # 在 start.sh 第 5 部分之前添加
  echo ">>> Starting extra services..."
  pm2 start /path/to/my-script.js
  service nginx start
  ```

## 🚀 快速开始

### 场景 A: 仓库级 Runner (Repository)
适用于单个仓库。
**REPO 格式**: `用户名/仓库名` (包含 `/`)

```bash
docker run -d \
  --name repo-runner \
  -e REPO="my-user/my-cool-repo" \
  -e ACCESS_TOKEN="ghp_YOUR_PAT..." \
  my-runner-image
```

### 场景 B: 组织级 Runner (Organization)
适用于整个组织下的所有仓库。
**REPO 格式**: `组织名` (不包含 `/`)

```bash
docker run -d \
  --name org-runner \
  -e REPO="My-Company-Org" \
  -e ACCESS_TOKEN="ghp_YOUR_PAT..." \
  my-runner-image
```

> **关于 ACCESS_TOKEN (PAT)**:
> 推荐使用 PAT (`repo` 权限或 `admin:org` 权限)，脚本会自动申请临时的注册 Token。
> 如果你必须使用手动获取的 `REGISTRATION_TOKEN`，请确保容器可持续运行，因为超过1小时后重启该 Token 会过期。

## ⚙️ 环境变量说明

| 变量名 | 必填 | 描述 |
| :--- | :---: | :--- |
| `REPO` | ✅ | **核心变量**。包含 `/` 视为仓库 (如 `user/repo`)，否则视为组织 (如 `my-org`)。 |
| `ACCESS_TOKEN` | ❌ | **推荐**。GitHub PAT，用于自动获取注册 Token。 |
| `REGISTRATION_TOKEN`| ❌ | 手动注册 Token。如果未提供 PAT，则此项必填 (组织级慎用)。 |
| `NAME` | ❌ | Runner 名称 (默认为容器 ID)。 |
| `GITHUB_SSH_USER` | ❌ | 设置后将自动拉取该 GitHub 用户的 SSH 公钥允许登录。 |

## 🔌 SSH 连接

容器暴露 **7450** 端口用于 SSH 连接。

1. 启动时设置 `GITHUB_SSH_USER=你的GitHub用户名`。
2. 连接命令：`ssh -p 7450 docker@<容器IP>`

## ⚠️ 安全说明

为了防止恶意的 Workflow 读取你的注册凭证，`start.sh` 在启动 Runner 主进程时使用了 `env -u` 策略：
- `ACCESS_TOKEN` 和 `REGISTRATION_TOKEN` 会在 Runner 启动前从环境变量中剔除。
- 这意味着你在 GitHub Actions 的 steps 中**无法**通过 `env.ACCESS_TOKEN` 访问这些值。

## 许可证

MIT
