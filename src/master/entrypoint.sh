#!/usr/bin/env bash
set -euo pipefail

CONF_DIR=/etc/salt/master.d
mkdir -p "$CONF_DIR"

{
    [ -z "${SALT_AUTO_ACCEPT:-}" ] || printf 'auto_accept: %s\n' "$SALT_AUTO_ACCEPT"
    [ -z "${SALT_MASTER_ID:-}" ] || printf 'id: %s\n' "$SALT_MASTER_ID"

    # Fires salt/presence/present (and /change) events on the event bus so
    # `salt-run manage.present`/`manage.status` reflect which minions are
    # actually connected right now - useful in Kubernetes, where minion pods
    # come and go independently of their accepted-key status.
    printf 'presence_events: %s\n' "${SALT_PRESENCE_EVENTS:-True}"

    # Keep pidfile/sock_dir off /var/run: the container runtime remounts
    # /run fresh (root-owned, 0755) on every pod start regardless of what's
    # baked into the image, so a non-root master can never mkdir under
    # /var/run/salt/master - same reasoning/pattern as
    # salt-minion-vcf/scripts/docker-entrypoint.sh's pidfile/sock_dir.
    printf 'pidfile: /var/cache/salt/master/master.pid\n'
    printf 'sock_dir: /var/cache/salt/master/.socks\n'
} > "$CONF_DIR/99-env.conf"

# Optional: pre-seed the master's own keypair (e.g. generated and registered
# with RaaS/the minion side out-of-band, then handed to this container as a
# Secret) instead of letting salt-master generate one on first start. Only
# applied when master.pem doesn't already exist, so a restarted/rescheduled
# container (persistent PKI volume) keeps its established identity rather
# than re-seeding on every start.
PKI_DIR=/etc/salt/pki/master
mkdir -p "$PKI_DIR"

if [ ! -s "$PKI_DIR/master.pem" ] \
    && [ -n "${SALT_MASTER_PRIVATE_KEY_B64:-}" ] && [ -n "${SALT_MASTER_PUBLIC_KEY_B64:-}" ]; then
    mkdir -p "$PKI_DIR"
    echo "${SALT_MASTER_PRIVATE_KEY_B64}" | base64 -d > "$PKI_DIR/master.pem"
    chmod 0400 "$PKI_DIR/master.pem"
    echo "${SALT_MASTER_PUBLIC_KEY_B64}" | base64 -d > "$PKI_DIR/master.pub"
    chmod 0644 "$PKI_DIR/master.pub"
    echo "Pre-seeded master keypair"
fi

# Optional: Salt master cluster mode (Salt 3007+; isolated filesystem mode
# needs 3008+). Enabled by setting SALT_CLUSTER_ID. See
# https://docs.saltproject.io/en/latest/topics/tutorials/master-cluster.html
#
#   SALT_CLUSTER_ID                  cluster_id
#   SALT_CLUSTER_PEERS               comma-separated peer hostnames; this
#                                    pod's own entry (matched on the short
#                                    hostname) is dropped, and each remaining
#                                    one is resolved to an IP because the
#                                    upstream docs only show IP peers
#   SALT_CLUSTER_SECRET              cluster_secret (authenticates joins)
#   SALT_CLUSTER_PKI_DIR             cluster_pki_dir
#   SALT_CLUSTER_POOL_PORT           cluster_pool_port (peer-to-peer RPC)
#   SALT_CLUSTER_ISOLATED_FILESYSTEM "true" -> cluster_isolated_filesystem
if [ -n "${SALT_CLUSTER_ID:-}" ]; then
    CLUSTER_CONF="$CONF_DIR/98-cluster.conf"
    PEER_IPS=""
    SELF="$(hostname -s 2>/dev/null || hostname)"

    IFS=',' read -r -a PEER_HOSTS <<< "${SALT_CLUSTER_PEERS:-}"
    for peer in "${PEER_HOSTS[@]:-}"; do
        [ -n "$peer" ] || continue
        [ "${peer%%.*}" != "$SELF" ] || continue

        # Peer pods may not exist yet when the whole StatefulSet starts at
        # once, so retry briefly; a peer that never resolves is skipped and
        # can still join us dynamically later (it lists us as *its* peer).
        ip=""
        for _ in $(seq 1 30); do
            # getent exits 2 for an unknown host; don't let pipefail/-e kill us.
            ip="$(getent hosts "$peer" | awk '{print $1; exit}' || true)"
            [ -z "$ip" ] || break
            sleep 1
        done
        if [ -n "$ip" ]; then
            PEER_IPS="$PEER_IPS $ip"
        else
            echo "WARNING: cluster peer $peer did not resolve; skipping" >&2
        fi
    done

    (
        umask 077
        {
            printf 'cluster_id: %s\n' "$SALT_CLUSTER_ID"
            printf 'cluster_pki_dir: %s\n' "${SALT_CLUSTER_PKI_DIR:-/etc/salt/pki/cluster}"
            [ -z "${SALT_CLUSTER_POOL_PORT:-}" ] || printf 'cluster_pool_port: %s\n' "$SALT_CLUSTER_POOL_PORT"
            [ -z "${SALT_CLUSTER_SECRET:-}" ] || printf 'cluster_secret: %s\n' "$SALT_CLUSTER_SECRET"
            if [ -n "$PEER_IPS" ]; then
                printf 'cluster_peers:\n'
                for ip in $PEER_IPS; do printf '  - %s\n' "$ip"; done
            fi
            if [ "${SALT_CLUSTER_ISOLATED_FILESYSTEM:-}" = "true" ]; then
                printf 'cluster_isolated_filesystem: True\n'
                printf 'keys.cache_driver: mmap_key\n'
            fi
        } > "$CLUSTER_CONF"
    )
    mkdir -p "${SALT_CLUSTER_PKI_DIR:-/etc/salt/pki/cluster}"
    echo "Rendered cluster config for cluster_id=$SALT_CLUSTER_ID"
fi

mkdir -p /var/cache/salt/master/.socks

if [ $# -eq 0 ]; then
    exec salt-master -l info
fi

exec "$@"
