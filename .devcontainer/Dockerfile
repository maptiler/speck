# Use the testing distribution, we need access to the newest version of pandoc.
FROM debian:forky

# Install dependencies.
# The Claude Code devcontainer feature installs Claude Code with npm, so it needs
# both nodejs and npm (Debian packages them separately).
RUN apt update --quiet \
 && apt install --quiet --yes --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        emscripten \
        git \
        liblua5.4-dev \
        nodejs \
        npm \
        pandoc \
        pkg-config

# Create local user.
RUN groupadd --gid 1000 debian \
 && useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash debian

# Create Claude configuration directory under the correct user.
RUN mkdir /home/debian/.claude \
 && chown debian:debian /home/debian/.claude
