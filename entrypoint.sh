#!/bin/sh
set -eu

HOSTKEY_DIR=/etc/ssh/host_keys
AUTH_KEYS=/home/agent/.ssh/authorized_keys

# Generate an ed25519 host key on first run only.
# Mount a volume at /etc/ssh/host_keys so the host identity survives
# container recreation (avoids MITM-style host-key-changed churn).
if [ ! -f "$HOSTKEY_DIR/ssh_host_ed25519_key" ]; then
    ssh-keygen -t ed25519 -N "" -f "$HOSTKEY_DIR/ssh_host_ed25519_key"
fi
chmod 600 "$HOSTKEY_DIR/ssh_host_ed25519_key"

# Install the agent's public key. Two options:
#   1. Pass it via env:    agent_AUTHORIZED_KEYS="ssh-ed25519 AAAA..."
#   2. Mount it read-only at /home/agent/.ssh/authorized_keys
if [ -n "${agent_AUTHORIZED_KEYS:-}" ]; then
    printf '%s\n' "$agent_AUTHORIZED_KEYS" > "$AUTH_KEYS"
fi

if [ ! -s "$AUTH_KEYS" ]; then
    echo "ERROR: no authorized key for user 'agent'." >&2
    echo "Set agent_AUTHORIZED_KEYS or mount an authorized_keys file." >&2
    exit 1
fi

# Tighten permissions unless the file is a read-only mount.
chmod 600 "$AUTH_KEYS" 2>/dev/null || true

# Run sshd in the foreground as the current (non-root) user, logging to
# stderr. Full path is required by sshd when re-executing itself.
exec /usr/sbin/sshd -D -e