# syntax=docker/dockerfile:1
ARG TARGET_IMAGE_REPOSITORY="docker.io/library"
ARG TARGET_IMAGE_NAME="oraclelinux"
ARG TARGET_IMAGE_TAG="10-slim"
ARG TARGET_IMAGE_DIGEST="sha256:8907e4c5317ce19cd361b0dc6be3a18680cd1800420db1d173316f6e6a109bac"
ARG BUILD_IMAGE_REPOSITORY=${TARGET_IMAGE_REPOSITORY}
ARG BUILD_IMAGE_NAME=${TARGET_IMAGE_NAME}
ARG BUILD_IMAGE_TAG=${TARGET_IMAGE_TAG}
ARG BUILD_IMAGE_DIGEST=${TARGET_IMAGE_DIGEST}

FROM --platform=${BUILDPLATFORM} ${BUILD_IMAGE_REPOSITORY}/${BUILD_IMAGE_NAME}:${BUILD_IMAGE_TAG}@${BUILD_IMAGE_DIGEST} AS build
ARG BUILDOS
ARG BUILDARCH

FROM ${TARGET_IMAGE_REPOSITORY}/${TARGET_IMAGE_NAME}:${TARGET_IMAGE_TAG}@${TARGET_IMAGE_DIGEST} AS target
ARG TARGETOS
ARG TARGETARCH

ADD [ \
        "https://cli.github.com/packages/rpm/gh-cli.repo", \
        "/etc/yum.repos.d/" \
    ]
RUN microdnf install --assumeyes --nodocs \
        libicu-74.2 \
        unzip-6.0 \
        ansible-core-2.16.14 \
        jq-1.7.1 \
        buildah-1.39.4 \
        fuse-overlayfs-1.14 \
        gh-2.76.2 \
        nodejs-npm-10.9.2 \
        java-21-openjdk-headless-21.0.8.0.9 \
        graphviz-9.0.0 \
        golang-1.24.6 \
    && microdnf clean all && rm -rf /var/cache/yum && rm -rf /var/cache/dnf && rm -rf /tmp/*

RUN npm install -g \
        @mermaid-js/mermaid-cli@11.9.0 \
        @iconify-json/devicon@1.2.42 \
        @openai/codex@0.23.0 \
    && npm cache clean --force && rm -rf /tmp/node-compile-cache && rm -rf /tmp/*

ADD --chmod=0500 \
    "https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3" \
    "/usr/local/bin/get-helm-3.sh"
RUN /usr/local/bin/get-helm-3.sh --version v3.18.6 --no-sudo \
    && rm -f /usr/local/bin/get-helm-3.sh \
    && chmod 0755 /usr/local/bin/helm

ARG TERRAFORM_VERSION="1.13.0"
ADD "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip" \
    "/tmp/terraform.zip"
RUN unzip -o /tmp/terraform.zip -d /usr/local/bin/ \
    && chmod 0755 /usr/local/bin/terraform \
    && rm -f /tmp/terraform.zip && rm -rf /tmp/* 

ARG STRUCTURIZR_CLI_VERSION="v2025.05.28"
RUN curl --fail --silent --show-error --location \
        "https://github.com/structurizr/cli/releases/download/${STRUCTURIZR_CLI_VERSION}/structurizr-cli.zip" \
        --output /tmp/structurizr-cli.zip \
    && unzip -o /tmp/structurizr-cli.zip -d /usr/local/bin/ \
    && rm -f /tmp/structurizr-cli.zip && rm -rf /tmp/*

ARG COSIGN_VERSION="2.5.3"
ARG COSIGN_URL="https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-${TARGETARCH}"
RUN curl --fail --silent --show-error --location \
        ${COSIGN_URL} \
        --output /tmp/cosign \
    && curl --fail --silent --show-error --location \
        ${COSIGN_URL}.sig \
        --output /tmp/cosign.sig \
    && install --mode=0755 --owner=root --group=root --preserve-timestamps --preserve-context /tmp/cosign /usr/local/bin/cosign \
    && rm -f /tmp/cosign && rm -rf /tmp/*

ARG MAIN_USER="gh-runner"
RUN useradd \
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
ADD --chmod=0500 --chown=${MAIN_USER}:${MAIN_USER} scripts/gh-runner.sh ./gh-runner.sh
RUN curl --fail --silent --show-error --location \
        "https://github.com/actions/runner/releases/download/v${GH_ACTION_RUNNER_VERSION}/actions-runner-linux-x64-${GH_ACTION_RUNNER_VERSION}.tar.gz" \
        --output ./actions-runner.tar.gz \
    && tar -xzf ./actions-runner.tar.gz
