# syntax=docker/dockerfile:1
#
# Master-only counterpart to the salt-minion-vcf/salt-minion-kubernetes
# minion images. Deliberately minimal: unlike either minion variant, this
# image doesn't need any Salt extensions (execution/state modules run on
# minions, not the master) or kubectl (the master never talks to a cluster
# API directly), so it skips both.
FROM ubuntu:24.04

# Pinned rather than "latest" so a given salt-master-image release tag
# reproducibly carries one specific Salt version - see CHANGELOG.md.
ARG SALT_VERSION=3008.2

LABEL org.opencontainers.image.title="Salt Master"
LABEL org.opencontainers.image.description="Salt Master runtime for VCF Salt"
LABEL org.opencontainers.image.licenses="Apache-2.0"

# ca-certificates/curl are OS packages that should track the latest security
# patches from the base image's own release channel rather than being frozen
# at build time - only Salt's own packages are version-pinned (SALT_VERSION).
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        tini \
        iproute2 \
        dnsutils \
        netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Salt's official bootstrap script, install type "onedir": fetches the same
# self-contained onedir tarball salt-ci-containers uses directly, without
# provisioning an apt repo + GPG key just to unpack it. -X skips starting any
# daemon at install time; the entrypoint starts salt-master as PID 1 instead.
# -N skips installing/configuring the minion service (this image is
# master-only); -M installs the master service, which the bootstrap script
# does not do by default.
#
# bootstrap.saltproject.io was decommissioned in Jan 2025; the script now
# ships as a GitHub release asset of saltstack/salt-bootstrap instead.
RUN --mount=type=secret,id=build_ca,target=/tmp/build-ca.crt,required=false \
    set -eu; \
    if [ -s /tmp/build-ca.crt ]; then \
        cp /tmp/build-ca.crt /usr/local/share/ca-certificates/build-ca.crt; \
        update-ca-certificates; \
    fi; \
    curl -fsSL -o /tmp/bootstrap-salt.sh \
        https://github.com/saltstack/salt-bootstrap/releases/latest/download/bootstrap-salt.sh; \
    curl -fsSL -o /tmp/bootstrap-salt.sh.sha256 \
        https://github.com/saltstack/salt-bootstrap/releases/latest/download/bootstrap-salt.sh.sha256; \
    printf '%s  /tmp/bootstrap-salt.sh\n' "$(cut -d' ' -f1 /tmp/bootstrap-salt.sh.sha256)" \
        > /tmp/bootstrap-salt.sh.sha256.check; \
    sha256sum -c /tmp/bootstrap-salt.sh.sha256.check; \
    if [ "$SALT_VERSION" = "latest" ]; then \
        sh /tmp/bootstrap-salt.sh -X -N -M -P onedir; \
    else \
        sh /tmp/bootstrap-salt.sh -X -N -M -P onedir "$SALT_VERSION"; \
    fi; \
    rm -f /tmp/bootstrap-salt.sh \
          /tmp/bootstrap-salt.sh.sha256 \
          /tmp/bootstrap-salt.sh.sha256.check; \
    if [ -s /tmp/build-ca.crt ]; then \
        rm -f /usr/local/share/ca-certificates/build-ca.crt; \
        update-ca-certificates >/dev/null; \
    fi

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# The bootstrap installation may create the salt account with a
# distribution-dependent UID/GID. Normalize it to 10001:10001 so
# Kubernetes can verify runAsNonRoot and directory ownership always matches.
# USER must remain numeric because Kubernetes cannot reliably verify a
# named image user when runAsNonRoot is enabled.
RUN set -eux; \
    if id salt >/dev/null 2>&1; then \
        groupmod --gid 10001 salt; \
        usermod --uid 10001 --gid 10001 salt; \
    else \
        groupadd --system --gid 10001 salt; \
        useradd --system --uid 10001 --gid 10001 \
            --no-create-home --shell /usr/sbin/nologin salt; \
    fi; \
    mkdir -p /etc/salt/pki/master \
             /var/cache/salt/master \
             /var/run/salt/master \
             /var/log/salt; \
    chown -R 10001:10001 \
        /etc/salt \
        /var/cache/salt \
        /var/run/salt \
        /var/log/salt

USER 10001:10001

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD nc -z 127.0.0.1 4505 && nc -z 127.0.0.1 4506s

VOLUME ["/etc/salt/pki/master"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
