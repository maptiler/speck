# Use the testing distribution, we need access to the newest version of pandoc.
FROM debian:forky AS base

# Install dependencies.
RUN apt update --quiet \
 && apt install --quiet --yes --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        git \
        liblua5.4-dev \
        pandoc \
        pkg-config

# Create local user.
RUN groupadd --gid 1000 debian \
 && useradd --uid 1000 --gid 1000 --create-home debian

# ============================================================================

FROM base AS jail

# Make sure that Claude always uses the development files.
ENV SPECK_BASE=/workspaces/speck/src

# Pre-create directory for Claude, otherwise it would be created by Docker under the root user.
RUN mkdir /home/debian/.claude \
 && chown debian:debian /home/debian/.claude

# Install gnupg for the custom APT repository below, and Python since Claude loves to use it.
RUN apt install --quiet --yes --no-install-recommends\
        gnupg \
        python3

# Configure Claude APT repository.
RUN install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL https://downloads.claude.ai/keys/claude-code.asc -o /etc/apt/keyrings/claude-code.asc \
 && echo "deb [signed-by=/etc/apt/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/stable stable main" > /etc/apt/sources.list.d/claude-code.list

# Install Claude.
RUN apt update --quiet \
 && apt install --quiet --yes --no-install-recommends claude-code
