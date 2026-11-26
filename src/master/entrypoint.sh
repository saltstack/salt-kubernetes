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
    # src/minion/kubernetes/entrypoint.sh's pidfile/sock_dir.
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
# https://docs.saltproject.io/en/3008/topics/tutorials/master-cluster.html
#
#   SALT_CLUSTER_ID                  cluster_id
#   SALT_CLUSTER_NODE_ADDRESS        this master's own IP, written as `interface:`.
#                                    Salt uses `interface` as the node identity
#                                    in the consensus layer and matches it
#                                    against peers' cluster_peers entries, so
#                                    it must be the real, peer-reachable IP
#                                    (not the 0.0.0.0 default)
#   SALT_CLUSTER_PEERS               comma-separated peer hostnames; this
#                                    pod's own entry (matched on the short
#                                    hostname) is dropped, and each remaining
#                                    one is resolved to an IP because the
#                                    upstream docs only show IP peers
#   SALT_CLUSTER_SECRET              cluster_secret (authenticates joins)
#   SALT_CLUSTER_PKI_DIR             cluster_pki_dir
#   SALT_CLUSTER_POOL_PORT           cluster_pool_port (peer-to-peer RPC)
#   SALT_CLUSTER_ISOLATED_FILESYSTEM "true" -> cluster_isolated_filesystem
#   SALT_CLUSTER_KEYS_CACHE_DRIVER   optional keys.cache_driver (e.g. mmap_key)
#   SALT_CLUSTER_AUTO_REPLACE_VOTERS cluster_auto_replace_voters (true/false)
#   SALT_CLUSTER_MIN_VOTERS          cluster_min_voters
if [ -n "${SALT_CLUSTER_ID:-}" ]; then
    CLUSTER_CONF="$CONF_DIR/98-cluster.conf"
    PEER_IPS=""
    SELF="$(hostname -s 2>/dev/null || hostname)"

    IFS=',' read -r -a PEER_HOSTS <<< "${SALT_CLUSTER_PEERS:-}"

    # Salt refuses to start a cluster member without at least one peer
    # ("Dynamic peer discovery is not supported"), so there is no founder
    # that can start alone. Wait (up to SALT_CLUSTER_PEER_WAIT_SECONDS) for
    # every other pod's DNS name to resolve - they all start together, so
    # this normally takes a few seconds. After the grace period, carry on
    # with whichever peers resolved, but fail loudly if none did.
    deadline=$((SECONDS + ${SALT_CLUSTER_PEER_WAIT_SECONDS:-120}))
    while :; do
        PEER_IPS=""
        unresolved=""
        for peer in "${PEER_HOSTS[@]:-}"; do
            [ -n "$peer" ] || continue
            [ "${peer%%.*}" != "$SELF" ] || continue

            # getent exits 2 for an unknown host; don't let pipefail/-e kill us.
            ip="$(getent hosts "$peer" | awk '{print $1; exit}' || true)"
            if [ -n "$ip" ]; then
                PEER_IPS="$PEER_IPS $ip"
            else
                unresolved="$unresolved $peer"
            fi
        done
        [ -n "$unresolved" ] || break
        [ "$SECONDS" -lt "$deadline" ] || break
        sleep 2
    done

    if [ -z "$PEER_IPS" ]; then
        echo "ERROR: none of the cluster peers resolved (${SALT_CLUSTER_PEERS:-<empty>}); a Salt master cluster needs at least one peer" >&2
        exit 1
    fi
    [ -z "$unresolved" ] || echo "WARNING: continuing without unresolved cluster peers:$unresolved" >&2

    (
        umask 077
        {
            printf 'cluster_id: %s\n' "$SALT_CLUSTER_ID"
            [ -z "${SALT_CLUSTER_NODE_ADDRESS:-}" ] || printf 'interface: %s\n' "$SALT_CLUSTER_NODE_ADDRESS"
            # The tutorial's cluster examples use the node's IP as the master
            # id, and peers are keyed by IP; the pod FQDN default does not
            # match. An explicit SALT_MASTER_ID still wins (99-env.conf).
            [ -n "${SALT_MASTER_ID:-}" ] || [ -z "${SALT_CLUSTER_NODE_ADDRESS:-}" ] || printf 'id: %s\n' "$SALT_CLUSTER_NODE_ADDRESS"
            printf 'cluster_pki_dir: %s\n' "${SALT_CLUSTER_PKI_DIR:-/etc/salt/pki/cluster}"
            [ -z "${SALT_CLUSTER_POOL_PORT:-}" ] || printf 'cluster_pool_port: %s\n' "$SALT_CLUSTER_POOL_PORT"
            [ -z "${SALT_CLUSTER_SECRET:-}" ] || printf 'cluster_secret: %s\n' "$SALT_CLUSTER_SECRET"
            if [ -n "$PEER_IPS" ]; then
                printf 'cluster_peers:\n'
                for ip in $PEER_IPS; do printf '  - %s\n' "$ip"; done
            fi
            if [ "${SALT_CLUSTER_ISOLATED_FILESYSTEM:-}" = "true" ]; then
                printf 'cluster_isolated_filesystem: True\n'
            fi
            # SALT_CLUSTER_KEYS_CACHE_DRIVER overrides keys.cache_driver
            # (localfs_key is Salt's default; Salt recommends mmap_key for
            # the isolated filesystem mode).
            [ -z "${SALT_CLUSTER_KEYS_CACHE_DRIVER:-}" ] || printf 'keys.cache_driver: %s\n' "$SALT_CLUSTER_KEYS_CACHE_DRIVER"
            # Voter replacement: a pod's IP is its cluster identity and changes
            # on every restart, so the old identity must be demoted and the
            # restarted pod promoted. Salt's defaults (auto-replace off,
            # min voters 3) never do that.
            [ -z "${SALT_CLUSTER_AUTO_REPLACE_VOTERS:-}" ] || printf 'cluster_auto_replace_voters: %s\n' "$SALT_CLUSTER_AUTO_REPLACE_VOTERS"
            [ -z "${SALT_CLUSTER_MIN_VOTERS:-}" ] || printf 'cluster_min_voters: %s\n' "$SALT_CLUSTER_MIN_VOTERS"
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
