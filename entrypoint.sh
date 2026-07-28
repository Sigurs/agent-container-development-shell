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
# Tighten permissions unless the volume is a read-only mount.
chmod 600 "$HOSTKEY_DIR/ssh_host_ed25519_key" 2>/dev/null || true

# Install the agent's public key. Two options:
#   1. Pass it via env:    AGENT_AUTHORIZED_KEYS="ssh-ed25519 AAAA..."
#   2. Mount it read-only at /home/agent/.ssh/authorized_keys
if [ -n "${AGENT_AUTHORIZED_KEYS:-}" ]; then
    printf '%s\n' "$AGENT_AUTHORIZED_KEYS" > "$AUTH_KEYS"
fi

if [ ! -s "$AUTH_KEYS" ]; then
    echo "ERROR: no authorized key for user 'agent'." >&2
    echo "Set agent_AUTHORIZED_KEYS or mount an authorized_keys file." >&2
    exit 1
fi

# Tighten permissions unless the file is a read-only mount.
chmod 600 "$AUTH_KEYS" 2>/dev/null || true

# sshd (UsePAM no) starts sessions with a blank env, so the container's
# k8s-injected vars (TZ, SEARXNG_URL, ...) never reach the login shell on
# their own. ~/.ssh/environment + PermitUserEnvironment is the standard
# way to forward them without PAM.
env | grep -Ev '^(HOME|USER|LOGNAME|SHELL|PATH|PWD|OLDPWD)=' > /home/agent/.ssh/environment
chmod 600 /home/agent/.ssh/environment

# Run sshd in the foreground as the current (non-root) user, logging to
# stderr. Full path is required by sshd when re-executing itself.
exec /usr/sbin/sshd -D -e