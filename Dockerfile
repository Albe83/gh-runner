# syntax=docker/dockerfile:1
ARG TARGET_IMAGE_REPOSITORY="docker.io/library"
ARG TARGET_IMAGE_NAME="oraclelinux"
ARG TARGET_IMAGE_TAG="10-slim"
ARG TARGET_IMAGE_DIGEST="sha256:8907e4c5317ce19cd361b0dc6be3a18680cd1800420db1d173316f6e6a109bac"
ARG BUILD_IMAGE_REPOSITORY="${TARGET_IMAGE_REPOSITORY}"
ARG BUILD_IMAGE_NAME=${TARGET_IMAGE_NAME}
ARG BUILD_IMAGE_TAG=${TARGET_IMAGE_TAG}
ARG BUILD_IMAGE_DIGEST=${TARGET_IMAGE_DIGEST}
FROM --platform=${BUILDPLATFORM} ${BUILD_IMAGE_REPOSITORY}/${BUILD_IMAGE_NAME}:${BUILD_IMAGE_TAG}@${BUILD_IMAGE_DIGEST} AS build
ARG BUILDOS
ARG BUILDARCH


FROM ${TARGET_IMAGE_REPOSITORY}/${TARGET_IMAGE_NAME}:${TARGET_IMAGE_TAG}@${TARGET_IMAGE_DIGEST} AS target
ARG TARGETOS
ARG TARGETARCH

ARG MAIN_USER="user"
RUN useradd --no-create-home --no-user-group --system --shell /bin/false --comment "Main User" ${MAIN_USER}

ADD [ \
        "https://cli.github.com/packages/rpm/gh-cli.repo", \
        "/etc/yum.repos.d/" \
    ]
RUN microdnf install --assumeyes --nodocs \
        unzip-6.0 \
        ansible-core-2.16.14 \
        jq-1.7.1 \
        buildah-1.39.4 \
        gh-2.76.2-1 \
        nodejs-npm-10.9.2 \
    && microdnf clean all && rm -rf /var/cache/yum && rm -rf /var/cache/dnf

RUN npm install -g \
        @mermaid-js/mermaid-cli@11.9.0 \
        @iconify-json/devicon@1.2.42 \
    && npm cache clean --force && rm -rf /tmp/node-compile-cache

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
    && rm -f /tmp/terraform.zip \
    && chmod 0755 /usr/local/bin/terraform

# USER ${MAIN_USER}
WORKDIR /