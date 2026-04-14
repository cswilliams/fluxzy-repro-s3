FROM ubuntu:noble

ARG FLUXZY_VERSION=1.35.25.62495

ENV DEBIAN_FRONTEND=noninteractive
ENV FLUXZY_VERSION=${FLUXZY_VERSION}
ENV FLUXZY_INSTALL_DIR=/opt/fluxzy/${FLUXZY_VERSION}
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

RUN apt-get update && apt-get install -y \
  ca-certificates \
  curl \
  iproute2 \
  iptables \
  openssl \
  procps \
  sudo \
  unzip \
  && rm -rf /var/lib/apt/lists/*

RUN groupadd --system fluxzy \
  && useradd --system --gid fluxzy --home-dir /var/lib/fluxzy --create-home --shell /usr/sbin/nologin fluxzy

RUN set -eux; \
  arch="$(dpkg --print-architecture)"; \
  case "${arch}" in \
    arm64) aws_arch="aarch64" ;; \
    amd64) aws_arch="x86_64" ;; \
    *) echo "Unsupported architecture for AWS CLI: ${arch}" >&2; exit 1 ;; \
  esac; \
  temp_dir="$(mktemp -d)"; \
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip" -o "${temp_dir}/awscliv2.zip"; \
  unzip -q "${temp_dir}/awscliv2.zip" -d "${temp_dir}"; \
  "${temp_dir}/aws/install"; \
  rm -rf "${temp_dir}"

RUN set -eux; \
  arch="$(dpkg --print-architecture)"; \
  case "${arch}" in \
    arm64) fluxzy_arch="arm64" ;; \
    amd64) fluxzy_arch="x64" ;; \
    *) echo "Unsupported architecture: ${arch}" >&2; exit 1 ;; \
  esac; \
  temp_dir="$(mktemp -d)"; \
  curl -fsSL "https://github.com/haga-rak/fluxzy.core/releases/download/v${FLUXZY_VERSION}/fluxzy-cli-${FLUXZY_VERSION}-linux-${fluxzy_arch}.tar.gz" -o "${temp_dir}/fluxzy.tar.gz"; \
  mkdir -p "${FLUXZY_INSTALL_DIR}"; \
  tar -xzf "${temp_dir}/fluxzy.tar.gz" -C "${FLUXZY_INSTALL_DIR}"; \
  ln -sf "${FLUXZY_INSTALL_DIR}/fluxzy" /usr/local/bin/fluxzy; \
  rm -rf "${temp_dir}"

COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
