# syntax=docker/dockerfile:1
ARG DEBIAN_FRONTEND=noninteractive
ARG NODE_MAJOR=22

# ── base: 共通システムパッケージ + ツールチェーン ──────────────────────────────
FROM debian:bookworm-slim AS base

ARG DEBIAN_FRONTEND
ARG NODE_MAJOR
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=1000

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential pkg-config libssl-dev ca-certificates \
    curl bash git procps locales unzip sudo \
  && rm -rf /var/lib/apt/lists/*

RUN echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Node.js LTS (NodeSource)
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*

# pnpm (corepack 経由)
RUN corepack enable && corepack prepare pnpm@latest --activate

# Non-root user
RUN groupadd --gid ${USER_GID} ${USERNAME} \
  && useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash ${USERNAME} \
  && echo "${USERNAME} ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
  && chmod 0440 /etc/sudoers.d/${USERNAME}

USER ${USERNAME}
WORKDIR /home/${USERNAME}

# Rust toolchain
ENV RUSTUP_HOME=/home/${USERNAME}/.rustup
ENV CARGO_HOME=/home/${USERNAME}/.cargo
ENV PATH=/home/${USERNAME}/.cargo/bin:$PATH

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y \
        --default-toolchain stable \
        --target wasm32-unknown-unknown \
  && $CARGO_HOME/bin/rustup component add rustfmt clippy rust-analyzer

# wasm-pack (公式バイナリインストーラ)
RUN curl https://rustwasm.github.io/wasm-pack/installer/init.sh -sSf | sh

# named volume マウントポイントを事前作成 (ownership を正しく設定するため)
RUN mkdir -p /home/${USERNAME}/.cargo/registry \
             /home/${USERNAME}/.cargo/git \
             /home/${USERNAME}/.local/share/pnpm/store

# ── dev: 開発用ステージ (devcontainer がこのステージを使う) ───────────────────
FROM base AS dev

RUN sudo mkdir -p /workspace && sudo chown ${USERNAME}:${USERNAME} /workspace
WORKDIR /workspace
CMD ["/bin/bash"]

# ── builder: ソースをコピーしてビルド ─────────────────────────────────────────
FROM base AS builder

COPY --chown=${USERNAME}:${USERNAME} rust-core/ /build/rust-core/
COPY --chown=${USERNAME}:${USERNAME} frontend/  /build/frontend/
COPY --chown=${USERNAME}:${USERNAME} build.sh   /build/

WORKDIR /build
RUN chmod +x build.sh && ./build.sh

# ── production: nginx で静的ファイル配信 ──────────────────────────────────────
FROM nginx:alpine AS production

COPY --from=builder /build/frontend/dist /usr/share/nginx/html

# WASM の Content-Type を正しく設定
RUN echo 'types { application/wasm wasm; }' > /etc/nginx/conf.d/wasm.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
