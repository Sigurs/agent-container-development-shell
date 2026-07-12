# Minimal SSH terminal environment for agent-agent
# Base: node slim (OpenSpec requires Node >= 20.19)
FROM node:24-bookworm-slim

# --- System packages: sshd, git, and basic file/editing tools ---
RUN apt-get update && apt-get install -y --no-install-recommends \
        openssh-server \
        git \
        ca-certificates \
        curl \
        gnupg \
        nano \
        vim-tiny \
        less \
        jq \
        ripgrep \
    && rm -rf /var/lib/apt/lists/*

# --- GitHub CLI from the official apt repo ---
RUN install -d -m 755 /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# --- OpenSpec (spec-driven development CLI) ---
RUN npm install -g @fission-ai/openspec@latest \
    && npm cache clean --force
ENV OPENSPEC_TELEMETRY=0

# --- Dedicated unprivileged user for the agent ---
# (remove the default 'node' user from the base image to keep the surface small)
# gid 0 + group-rwx: works even when a runtime overrides the UID at start
# (the GID stays 0 and these dirs are already group-writable).
RUN userdel -r node 2>/dev/null || true \
    && useradd --create-home --shell /bin/bash --uid 1000 --gid 0 agent \
    && install -d -m 770 -o agent -g 0 /home/agent/.ssh \
    && install -d -m 770 -o agent -g 0 /home/agent/work

# --- sshd setup (runs as the unprivileged 'agent' user) ---
# A non-root sshd cannot setuid, so it can only accept logins as the user
# it runs as — exactly the single-user model this container wants.
RUN install -d -m 770 -o agent -g 0 /etc/ssh/host_keys
COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh \
    && chown agent:0 /etc/ssh/sshd_config \
    && chmod 660 /etc/ssh/sshd_config

# Persist host keys across container recreation by mounting a volume here
VOLUME ["/etc/ssh/host_keys"]

USER agent
WORKDIR /home/agent/work
EXPOSE 2222

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD bash -c 'exec 3<>/dev/tcp/127.0.0.1/2222' || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]