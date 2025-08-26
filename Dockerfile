# syntax=docker/dockerfile:1
ARG IMAGE_NAME="gh-runner"

ARG BASE_IMAGE_REPOSITORY="docker.io/library"
ARG BASE_IMAGE_NAME="oraclelinux"
ARG BASE_IMAGE_TAG="9-slim"
ARG BASE_IMAGE_DIGEST="sha256:70350be019050cb2eb63d0f65c3053c90fdb78069a10a1ddef24981550201d30"

FROM ${BASE_IMAGE_REPOSITORY}/${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG}@${BASE_IMAGE_DIGEST} AS base
ARG TARGETOS
ARG TARGETARCH
ARG IMAGE_NAME

FROM base AS dnf
ARG DNF_CONF_DIR="/etc/dnf/"
COPY --chown=root:root --chmod=0644 files${DNF_CONF_DIR}* ${DNF_CONF_DIR}
ARG RPM_REPO_DIR="/etc/yum.repos.d/"
COPY --chown=root:root --chmod=0644 files${RPM_REPO_DIR}* ${RPM_REPO_DIR}
ARG DNF_CMD='dnf() { microdnf --setopt=install_weak_deps=0 --setopt=keepcache=1 --nodocs --assumeyes --nobest --refresh "$@"; }'
RUN --mount=id=${IMAGE_NAME}-tmp,type=tmpfs,target=/tmp \
    --mount=id=${IMAGE_NAME}-run,type=tmpfs,target=/var/run \
    --mount=id=${IMAGE_NAME}-log,type=cache,sharing=locked,target=/var/log \
    --mount=id=${IMAGE_NAME}-cache,type=cache,sharing=locked,target=/var/cache \
    set -Eeuo pipefail && eval ${DNF_CMD} \
    && dnf makecache

ARG DNF_REQUIRED_MODULES="nodejs:22"
ARG DNF_REQUIRED_PACKAGES="go npm gh java-21-openjdk-headless"
RUN --mount=id=${IMAGE_NAME}-tmp,type=tmpfs,target=/tmp \
    --mount=id=${IMAGE_NAME}-run,type=tmpfs,target=/var/run \
    --mount=id=${IMAGE_NAME}-log,type=cache,sharing=locked,target=/var/log \
    --mount=id=${IMAGE_NAME}-cache,type=cache,sharing=locked,target=/var/cache \
    set -Eeuo pipefail && eval ${DNF_CMD} \
    && dnf module enable ${DNF_REQUIRED_MODULES} \
    && dnf install ${DNF_REQUIRED_PACKAGES} \
    && dnf module disable ${DNF_REQUIRED_MODULES}

FROM dnf AS system-config
RUN --mount=id=${IMAGE_NAME}-tmp,type=tmpfs,target=/tmp \
    --mount=id=${IMAGE_NAME}-run,type=tmpfs,target=/var/run \
    --mount=id=${IMAGE_NAME}-log,type=cache,sharing=locked,target=/var/log \
    --mount=id=${IMAGE_NAME}-cache,type=cache,sharing=locked,target=/var/cache \
    --mount=id=${IMAGE_NAME}-home-root-cache,type=cache,sharing=locked,target=/root/.cache \
    set -Eeuo pipefail && eval ${DNF_CMD} \
    && go env -w GOBIN=/usr/local/bin GOCACHE=/var/cache/go-build \
    && npm config --global delete python && npm config --global set cache /var/cache/npm \
    && npm install --global --omit=dev --omit=optional --omit=peer node@24 \
    && npm install --global --omit=dev --omit=optional --omit=peer npm \
        && alternatives --install /usr/bin/npm npm /usr/local/bin/npm 1000 \
    && dnf remove npm nodejs nodejs-libs

FROM system-config AS download-actions-runner
ARG GH_ACTION_RUNNER_VERSION="2.328.0"
RUN --mount=id=${IMAGE_NAME}-home-root,type=cache,sharing=locked,target=/root,source=/root,from=system-config \
    set -Eeuo pipefail \
    && curl --fail --silent --show-error --location \
         "https://github.com/actions/runner/releases/download/v${GH_ACTION_RUNNER_VERSION}/actions-runner-${TARGETOS}-x64-${GH_ACTION_RUNNER_VERSION}.tar.gz" \
         --output /tmp/actions-runner.tar.gz \
    && mkdir -p /tmp/actions-runner \
    && eval ${DNF_CMD} \
    && dnf install gzip \
    && cd /tmp/actions-runner \
    && tar zxvf /tmp/actions-runner.tar.gz

FROM system-config AS gh-runner-user
ARG USER="gh-runner"
ARG GH_ACTION_RUNNER_VERSION="2.328.0"
RUN --mount=id=${IMAGE_NAME}-tmp,type=tmpfs,target=/tmp \
    --mount=id=${IMAGE_NAME}-run,type=tmpfs,target=/var/run \
    --mount=id=${IMAGE_NAME}-log,type=cache,sharing=locked,target=/var/log \
    --mount=id=${IMAGE_NAME}-cache,type=cache,sharing=locked,target=/var/cache \
    --mount=id=${IMAGE_NAME}-home-root,type=cache,sharing=locked,target=/root,source=/root,from=system-config \
    set -Eeuo pipefail \
    && useradd --system --shell /bin/false --create-home --comment "GitHub Actions Runner" ${USER}
COPY --from=download-actions-runner --chown=${USER}:${USER} --chmod=0550 /tmp/actions-runner /home/${USER}
COPY --chown=${USER}:${USER} --chmod=0550 files/home/${USER}/* /home/${USER}/

FROM gh-runner-user AS ai-agents
RUN --mount=id=${IMAGE_NAME}-tmp,type=tmpfs,target=/tmp \
    --mount=id=${IMAGE_NAME}-run,type=tmpfs,target=/var/run \
    --mount=id=${IMAGE_NAME}-log,type=cache,sharing=locked,target=/var/log \
    --mount=id=${IMAGE_NAME}-cache,type=cache,sharing=locked,target=/var/cache \
    --mount=id=${IMAGE_NAME}-home-root,type=cache,sharing=locked,target=/root,source=/root,from=system-config \
    set -Eeuo pipefail && eval ${DNF_CMD} \
    && npm install --global --omit=dev --omit=optional --omit=peer @openai/codex \
        && alternatives --install /usr/bin/codex codex /usr/local/lib/node_modules/node/bin/codex 1000

FROM ai-agents AS iac-tools
RUN --mount=id=${IMAGE_NAME}-tmp,type=tmpfs,target=/tmp \
    --mount=id=${IMAGE_NAME}-run,type=tmpfs,target=/var/run \
    --mount=id=${IMAGE_NAME}-log,type=cache,sharing=locked,target=/var/log \
    --mount=id=${IMAGE_NAME}-cache,type=cache,sharing=locked,target=/var/cache \
    --mount=id=${IMAGE_NAME}-home-root,type=cache,sharing=locked,target=/root,source=/root,from=system-config \
    set -Eeuo pipefail && eval ${DNF_CMD} \
    && dnf install ansible-core terraform

ARG PKG_NAME="helm.sh/helm/v3/cmd/helm"
ARG PKG_VERSION="latest"
ARG BIN_NAME="helm"
RUN --mount=id=${IMAGE_NAME}-tmp,type=tmpfs,target=/tmp \
    --mount=id=${IMAGE_NAME}-run,type=tmpfs,target=/var/run \
    --mount=id=${IMAGE_NAME}-log,type=cache,sharing=locked,target=/var/log \
    --mount=id=${IMAGE_NAME}-cache,type=cache,sharing=locked,target=/var/cache \
    --mount=id=${IMAGE_NAME}-home-root,type=cache,sharing=locked,target=/root,source=/root,from=system-config \
    set -Eeuo pipefail && eval ${DNF_CMD} \
    && go install ${PKG_NAME}@${PKG_VERSION} \
        && alternatives --install /usr/bin/${BIN_NAME} ${BIN_NAME} /usr/local/bin/${BIN_NAME} 1000

FROM iac-tools AS container-tools
RUN --mount=id=${IMAGE_NAME}-tmp,type=tmpfs,target=/tmp \
    --mount=id=${IMAGE_NAME}-run,type=tmpfs,target=/var/run \
    --mount=id=${IMAGE_NAME}-log,type=cache,sharing=locked,target=/var/log \
    --mount=id=${IMAGE_NAME}-cache,type=cache,sharing=locked,target=/var/cache \
    --mount=id=${IMAGE_NAME}-home-root,type=cache,sharing=locked,target=/root,source=/root,from=system-config \
    set -Eeuo pipefail && eval ${DNF_CMD} \
    && dnf install \
        buildah fuse-overlayfs \
        trivy

ARG PKG_NAME="github.com/sigstore/cosign/v2/cmd/cosign"
ARG PKG_VERSION="latest"
ARG BIN_NAME="cosign"
RUN --mount=id=${IMAGE_NAME}-tmp,type=tmpfs,target=/tmp \
    --mount=id=${IMAGE_NAME}-run,type=tmpfs,target=/var/run \
    --mount=id=${IMAGE_NAME}-log,type=cache,sharing=locked,target=/var/log \
    --mount=id=${IMAGE_NAME}-cache,type=cache,sharing=locked,target=/var/cache \
    --mount=id=${IMAGE_NAME}-home-root,type=cache,sharing=locked,target=/root,source=/root,from=system-config \
    set -Eeuo pipefail && eval ${DNF_CMD} \
    && go install ${PKG_NAME}@${PKG_VERSION} \
        && alternatives --install /usr/bin/${BIN_NAME} ${BIN_NAME} /usr/local/bin/${BIN_NAME} 1000

ARG PKG_NAME="github.com/anchore/syft/cmd/syft"
ARG PKG_VERSION="latest"
ARG BIN_NAME="syft"
RUN --mount=id=${IMAGE_NAME}-tmp,type=tmpfs,target=/tmp \
    --mount=id=${IMAGE_NAME}-run,type=tmpfs,target=/var/run \
    --mount=id=${IMAGE_NAME}-log,type=cache,sharing=locked,target=/var/log \
    --mount=id=${IMAGE_NAME}-cache,type=cache,sharing=locked,target=/var/cache \
    --mount=id=${IMAGE_NAME}-home-root,type=cache,sharing=locked,target=/root,source=/root,from=system-config \
    set -Eeuo pipefail && eval ${DNF_CMD} \
    && go install ${PKG_NAME}@${PKG_VERSION} \
        && alternatives --install /usr/bin/${BIN_NAME} ${BIN_NAME} /usr/local/bin/${BIN_NAME} 1000

FROM system-config AS download-structurizr
ARG STRUCTURIZR_CLI_VERSION="v2025.05.28"
RUN --mount=id=${IMAGE_NAME}-home-root,type=cache,sharing=locked,target=/root,source=/root,from=system-config \
    set -Eeuo pipefail \
    && curl --fail --silent --show-error --location \
        "https://github.com/structurizr/cli/releases/download/${STRUCTURIZR_CLI_VERSION}/structurizr-cli.zip" \
         --output /tmp/structurizr-cli.zip \
    && mkdir -p /tmp/structurizr-cli \
    && eval ${DNF_CMD} && dnf install unzip && unzip -o /tmp/structurizr-cli.zip -d /tmp/structurizr-cli/

FROM container-tools AS arch-tools
RUN --mount=id=${IMAGE_NAME}-tmp,type=tmpfs,target=/tmp \
    --mount=id=${IMAGE_NAME}-run,type=tmpfs,target=/var/run \
    --mount=id=${IMAGE_NAME}-log,type=cache,sharing=locked,target=/var/log \
    --mount=id=${IMAGE_NAME}-cache,type=cache,sharing=locked,target=/var/cache \
    --mount=id=${IMAGE_NAME}-home-root,type=cache,sharing=locked,target=/root,source=/root,from=system-config \
    set -Eeuo pipefail && eval ${DNF_CMD} \
    && npm install --global --omit=dev --omit=optional --omit=peer @mermaid-js/mermaid-cli @iconify-json/devicon

RUN --mount=id=${IMAGE_NAME}-tmp,type=tmpfs,target=/tmp \
    --mount=id=${IMAGE_NAME}-run,type=tmpfs,target=/var/run \
    --mount=id=${IMAGE_NAME}-log,type=cache,sharing=locked,target=/var/log \
    --mount=id=${IMAGE_NAME}-cache,type=cache,sharing=locked,target=/var/cache \
    --mount=id=${IMAGE_NAME}-home-root,type=cache,sharing=locked,target=/root,source=/root,from=system-config \
    set -Eeuo pipefail && eval ${DNF_CMD} && cd /root \
    && git clone https://github.com/adr/ad-guidance-tool && cd ad-guidance-tool \
    && go install && alternatives --install /usr/bin/adg adg /usr/local/bin/adg 1000

COPY --from=download-structurizr --chown=root:root --chmod=0555 \
    /tmp/structurizr-cli/ \
    /usr/local/bin/

FROM arch-tools AS other-tools
ARG PKG_NAME="github.com/rclone/rclone"
ARG PKG_VERSION="latest"
ARG BIN_NAME="rclone"
RUN --mount=id=${IMAGE_NAME}-tmp,type=tmpfs,target=/tmp \
    --mount=id=${IMAGE_NAME}-run,type=tmpfs,target=/var/run \
    --mount=id=${IMAGE_NAME}-log,type=cache,sharing=locked,target=/var/log \
    --mount=id=${IMAGE_NAME}-cache,type=cache,sharing=locked,target=/var/cache \
    --mount=id=${IMAGE_NAME}-home-root,type=cache,sharing=locked,target=/root,source=/root,from=system-config \
    set -Eeuo pipefail && eval ${DNF_CMD} \
    && go install ${PKG_NAME}@${PKG_VERSION} \
        && alternatives --install /usr/bin/${BIN_NAME} ${BIN_NAME} /usr/local/bin/${BIN_NAME} 1000

FROM other-tools AS final
WORKDIR /home/${USER}
USER ${USER}
ENV GH_HOST="github.com"
ENV GH_OWNER=""
ENV GH_REPO=""
ENV GH_SCHEMA="https"
ENV GH_URL="${GH_SCHEMA}://${GH_HOST}"
ENV GH_URL_REPO="${GH_URL}/${GH_OWNER}/${GH_REPO}"
ENV GH_TOKEN_FILE="/home/${USER}/.gh/token.txt"
ENV GH_RUNNER_LABELS=""