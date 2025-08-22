# syntax=docker/dockerfile:1
ARG TARGET_IMAGE_REPOSITORY="docker.io/library"
ARG TARGET_IMAGE_NAME="oraclelinux"
ARG TARGET_IMAGE_TAG="9-slim"
ARG TARGET_IMAGE_DIGEST="sha256:70350be019050cb2eb63d0f65c3053c90fdb78069a10a1ddef24981550201d30"
ARG BUILD_IMAGE_REPOSITORY=${TARGET_IMAGE_REPOSITORY}
ARG BUILD_IMAGE_NAME=${TARGET_IMAGE_NAME}
ARG BUILD_IMAGE_TAG=${TARGET_IMAGE_TAG}
ARG BUILD_IMAGE_DIGEST=${TARGET_IMAGE_DIGEST}

FROM --platform=${BUILDPLATFORM} ${BUILD_IMAGE_REPOSITORY}/${BUILD_IMAGE_NAME}:${BUILD_IMAGE_TAG}@${BUILD_IMAGE_DIGEST} AS build
ARG BUILDOS
ARG BUILDARCH

FROM --platform=${TARGETPLATFORM} ${TARGET_IMAGE_REPOSITORY}/${TARGET_IMAGE_NAME}:${TARGET_IMAGE_TAG}@${TARGET_IMAGE_DIGEST} AS target
ARG TARGETOS
ARG TARGETARCH

ARG DNF_CONF_DIR="/etc/dnf/"
COPY --chown=root:root --chmod=0644 files${DNF_CONF_DIR}* ${DNF_CONF_DIR}
ARG RPM_REPO_DIR="/etc/yum.repos.d/"
COPY --chown=root:root --chmod=0644 files${RPM_REPO_DIR}* ${RPM_REPO_DIR}
RUN --mount=type=cache,target=/tmp \
    --mount=type=cache,target=/var/run \
    --mount=type=cache,target=/var/log \
    --mount=type=cache,target=/var/cache \
    set -Eeuo pipefail; \
    microdnf --refresh --assumeyes --nobest --nodocs --refresh --setopt=install_weak_deps=0 module enable \
        nodejs:22 \
    && microdnf --refresh install --assumeyes --nobest --nodocs --refresh --setopt=install_weak_deps=0 \
        jq \
        buildah fuse-overlayfs \
        gh \
        ansible-core terraform \
        npm \
        unzip java-21-openjdk-headless graphviz \
        libicu \
        trivy

RUN --mount=type=cache,target=/tmp \
    --mount=type=cache,target=/var/run \
    --mount=type=cache,target=/var/log \
    --mount=type=cache,target=/var/cache \
    set -Eeuo pipefail; \
    npm install -g npm && npm install -g \
        @mermaid-js/mermaid-cli \
        @iconify-json/devicon \
        @openai/codex \
    && npm cache clean --force && rm -rf /tmp/node-compile-cache && rm -rf /tmp/*

ADD --chmod=0500 \
    "https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3" \
    "/usr/local/bin/get-helm-3.sh"
RUN --mount=type=cache,target=/tmp \
    --mount=type=cache,target=/var/run \
    --mount=type=cache,target=/var/log \
    --mount=type=cache,target=/var/cache \
    set -Eeuo pipefail; \
    /usr/local/bin/get-helm-3.sh --version v3.18.6 --no-sudo \
    && rm -f /usr/local/bin/get-helm-3.sh \
    && chmod 0755 /usr/local/bin/helm

ARG STRUCTURIZR_CLI_VERSION="v2025.05.28"
RUN --mount=type=cache,target=/tmp \
    --mount=type=cache,target=/var/run \
    --mount=type=cache,target=/var/log \
    --mount=type=cache,target=/var/cache \
    set -Eeuo pipefail; \
    curl --fail --silent --show-error --location \
        "https://github.com/structurizr/cli/releases/download/${STRUCTURIZR_CLI_VERSION}/structurizr-cli.zip" \
        --output /tmp/structurizr-cli.zip \
    && unzip -o /tmp/structurizr-cli.zip -d /usr/local/bin/ \
    && rm -f /tmp/structurizr-cli.zip && rm -rf /tmp/*

ARG COSIGN_VERSION="2.5.3"
ARG COSIGN_URL="https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-${TARGETARCH}"
RUN --mount=type=cache,target=/tmp \
    --mount=type=cache,target=/var/run \
    --mount=type=cache,target=/var/log \
    --mount=type=cache,target=/var/cache \
    set -Eeuo pipefail; \
    curl --fail --silent --show-error --location \
        ${COSIGN_URL} \
        --output /tmp/cosign \
    && install --mode=0755 --owner=root --group=root --preserve-timestamps --preserve-context /tmp/cosign /usr/local/bin/cosign \
    && rm -f /tmp/cosign && rm -rf /tmp/*

ARG SYFT_VERSION="v1.31.0"
RUN --mount=type=cache,target=/tmp \
    --mount=type=cache,target=/var/run \
    --mount=type=cache,target=/var/log \
    --mount=type=cache,target=/var/cache \
    set -Eeuo pipefail; \
    curl --fail --silent --show-error --location \
        "https://get.anchore.io/syft" | sh -s -- -b /usr/local/bin -v ${SYFT_VERSION}


ARG MAIN_USER="gh-runner"
RUN --mount=type=cache,target=/tmp \
    --mount=type=cache,target=/var/run \
    --mount=type=cache,target=/var/log \
    --mount=type=cache,target=/var/cache \
    set -Eeuo pipefail; \
    useradd \
    #--no-create-home \
    #--no-user-group \
    --system \
    --shell /bin/false \
    --comment "Main User" \
    ${MAIN_USER}
USER ${MAIN_USER}
WORKDIR /home/${MAIN_USER}

ARG GH_ACTION_RUNNER_VERSION="2.328.0"
ENV RUNNER_ALLOW_RUNASROOT=0
ENV GITHUB_URL=""
ENV GITHUB_TOKEN=""
ENV GITHUB_LABELS=""
ADD --chmod=0500 --chown=${MAIN_USER}:${MAIN_USER} files/gh-runner.sh ./gh-runner.sh
RUN --mount=type=cache,target=/tmp \
    --mount=type=cache,target=/var/run \
    --mount=type=cache,target=/var/log \
    set -Eeuo pipefail; \
    curl --fail --silent --show-error --location \
        "https://github.com/actions/runner/releases/download/v${GH_ACTION_RUNNER_VERSION}/actions-runner-linux-x64-${GH_ACTION_RUNNER_VERSION}.tar.gz" \
        --output ./actions-runner.tar.gz \
    && tar -xzf ./actions-runner.tar.gz
