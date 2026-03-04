# Multi-Copilot Base Development Container
#
# Minimal image with tools needed for Copilot CLI + MCP servers.
# Add your project's language runtimes below.

FROM mcr.microsoft.com/devcontainers/base:bookworm

# Install minimal dependencies
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get install -y --no-install-recommends \
        git gettext-base curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js (LTS) - needed for npm-based MCP servers
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y gh \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub Copilot CLI
RUN npm install -g @githubnext/github-copilot-cli

# ═══════════════════════════════════════════════════════════════════════════
# ADD YOUR PROJECT'S DEPENDENCIES BELOW
# ═══════════════════════════════════════════════════════════════════════════

# Verify installations
RUN node --version && npm --version && gh --version
