FROM ubuntu:22.04

# 定义构建参数
ARG RUNNER_VERSION="2.317.0"
ARG DEBIAN_FRONTEND=noninteractive

# 设置环境变量 
ENV TZ=Asia/Shanghai
ENV LANG=zh_CN.UTF-8
ENV LANGUAGE=zh_CN:zh
ENV LC_ALL=zh_CN.UTF-8
ENV JAVA_HOME=/usr/lib/jvm/temurin-8-jdk-amd64
ENV PATH=$JAVA_HOME/bin:$PATH

# ==============================================================================
# 1. 执行系统级安装 (运行 build.sh)
# ==============================================================================
COPY build.sh /tmp/build.sh
RUN chmod +x /tmp/build.sh && /tmp/build.sh && rm /tmp/build.sh

# ==============================================================================
# 2. 用户配置 (Docker User)
# ==============================================================================
# 创建 docker 用户 (UID 1000)
RUN useradd -m -u 1000 -s /bin/bash docker \
    && echo "docker ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# 配置 NPM 全局路径
RUN mkdir -p /home/docker/.npm-global \
    && chown -R docker:docker /home/docker/.npm-global

ENV NPM_CONFIG_PREFIX=/home/docker/.npm-global
ENV PATH=$PATH:/home/docker/.npm-global/bin:/home/docker/.local/bin

# ==============================================================================
# 3. Actions Runner 安装 (在 User 目录下)
# ==============================================================================
# Runner 必须安装在用户目录下，且依赖版本号 ARG，保留在 Dockerfile 比较灵活
WORKDIR /home/docker
RUN mkdir actions-runner && cd actions-runner \
    && curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && tar xzf actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && ./bin/installdependencies.sh \
    && rm actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && chown -R docker:docker /home/docker/actions-runner

# ==============================================================================
# 4. 用户级工具安装 (NPM, Python Tools)
# ==============================================================================
USER docker

# 安装 NPM 全局包 & Pipx 工具
# 注意：这些是安装在 /home/docker 下的，属于用户空间配置
RUN npm install -g yarn pnpm pm2 edgeone vercel @google/gemini-cli \
    && pipx ensurepath

# ==============================================================================
# 5. 启动配置
# ==============================================================================
USER root

# 准备 SSH 运行目录
RUN mkdir -p /run/sshd && chmod 755 /run/sshd

# 确保权限正确
RUN chown -R docker:docker /home/docker

COPY --chmod=+x start.sh /start.sh

USER docker
ENTRYPOINT ["/start.sh"]
