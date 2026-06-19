# Self-hosted GitHub Actions Runner (Repo & Org Supported)

[English](./README.md)

这是一个功能强大的 GitHub Actions 自托管 Runner 镜像，**完美支持组织级 (Organization) 和仓库级 (Repository) 两种注册模式**。

镜像设计高度模块化，你可以轻松地通过修改脚本来定制构建环境或添加启动命令。

## ✨ 核心特性

- **双模式支持**: 智能识别 `REPO` 变量，自动适配 **组织级** 或 **仓库级** 注册流程。
- **JIT 模式 (推荐)**: 使用 Just-In-Time 运行器配置，通过 Fine-Grained Token 实现最小权限控制，无需长期有效的注册令牌。
- **预装全能环境**:
  - Node.js 22, Java 8 (Temurin), .NET 6.0, Python 3 + Pipx
  - 常用工具: Maven, Git, PM2, EdgeOne/Vercel CLI
- **安全优先**: 启动时自动剥离敏感 Token，防止 Job 读取；非 Root 用户运行。

## 🚀 快速开始

### 方式 A: JIT 模式 (推荐)

使用 Fine-Grained Token，仅需最小权限。每次任务获取新的 JIT 配置，执行完成后运行器自动注销。

**Token 设置**: 创建 Fine-Grained Personal Access Token，添加以下权限：
- **组织级别**: `Self-hosted runners` → `Read and Write`
- **仓库级别**: `Actions` → `Read and Write`

**获取运行器组 ID**:
```bash
# 组织级运行器
curl -s -H "Authorization: Bearer YOUR_TOKEN" \
  https://api.github.com/orgs/ORG_NAME/actions/runners/groups | jq '.runner_groups[].id'

# 仓库级运行器 (group ID 通常为 1)
curl -s -H "Authorization: Bearer YOUR_TOKEN" \
  https://api.github.com/repos/OWNER/REPO/actions/runners/groups | jq '.runner_groups[].id'
```

**运行**:
```bash
docker run -d \
  --name jit-runner \
  -e REPO="My-Company-Org" \
  -e ACCESS_TOKEN="github_pat_XXXX" \
  -e USE_JIT="true" \
  -e RUNNER_GROUP_ID="1" \
  my-runner-image
```

### 方式 B: 传统模式

使用 Classic PAT，需要较宽泛的权限 (`repo` 或 `admin:org` scope)。

```bash
# 仓库级 Runner
docker run -d \
  --name repo-runner \
  -e REPO="my-user/my-cool-repo" \
  -e ACCESS_TOKEN="ghp_YOUR_PAT..." \
  my-runner-image

# 组织级 Runner
docker run -d \
  --name org-runner \
  -e REPO="My-Company-Org" \
  -e ACCESS_TOKEN="ghp_YOUR_PAT..." \
  my-runner-image
```

> **关于 ACCESS_TOKEN**:
> - **JIT 模式**: 使用 Fine-Grained Token，仅需 `Self-hosted runners` 权限，权限最小、最安全。
> - **传统模式**: 使用 Classic PAT，需要 `repo` 或 `admin:org` scope，脚本会自动申请临时注册 Token。
> - 如果必须使用手动获取的 `REGISTRATION_TOKEN`，请确保容器可持续运行，因为超过1小时后重启该 Token 会过期。

## ⚙️ 环境变量说明

| 变量名 | 必填 | 描述 |
| :--- | :---: | :--- |
| `REPO` | ✅ | **核心变量**。包含 `/` 视为仓库 (如 `user/repo`)，否则视为组织 (如 `my-org`)。 |
| `USE_JIT` | ❌ | 设置为 `true` 启用 JIT 模式 (推荐)。 |
| `ACCESS_TOKEN` | ✅* | GitHub PAT (Classic) 或 Fine-Grained Token，用于自动注册。 |
| `RUNNER_GROUP_ID` | JIT | **仅 JIT 模式**。要加入的运行器组 ID。 |
| `REGISTRATION_TOKEN`| ❌ | 手动注册 Token。如果未提供 PAT，则此项必填 (组织级慎用)。 |
| `NAME` | ❌ | Runner 名称 (默认为容器 ID)。 |

> \* 当未提供 `REGISTRATION_TOKEN` 时必填。

### JIT 模式 vs 传统模式

| | JIT 模式 | 传统模式 |
|---|---|---|
| Token 类型 | Fine-Grained PAT | Classic PAT |
| 所需权限 | `Self-hosted runners` (读写) | `repo` 或 `admin:org` |
| 注册方式 | JIT API → `run.sh --jitconfig` | `config.sh` → `run.sh` |
| Token 有效期 | 每次任务一次性使用 | 长期有效 |
| 运行器生命周期 | 临时 (执行后自动注销) | 持久注册 |
| 安全性 | ✅ 最小权限 | ⚠️ 较宽泛权限 |

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

## ⚠️ 安全说明

为了防止恶意的 Workflow 读取你的注册凭证，`start.sh` 在启动 Runner 主进程时使用了 `env -u` 策略：
- `ACCESS_TOKEN` 和 `REGISTRATION_TOKEN` 会在 Runner 启动前从环境变量中剔除。
- 这意味着你在 GitHub Actions 的 steps 中**无法**通过 `env.ACCESS_TOKEN` 访问这些值。
- 在 JIT 模式下，Token 也会在每次任务执行前被移除。

## 许可证

MIT
