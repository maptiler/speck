# This file describes the image that is used both for the GitHub action
# and as the base for VS Code devcontainers in client repositories. It
# is based on our devcontainer version, but is split into two phases to
# minimize the size of the image.

# ============================================================================

FROM debian:forky AS build

RUN apt update --quiet \
 && apt install --quiet --yes --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        liblua5.4-dev \
        pkg-config

COPY src/* /usr/local/src/speck/src/
COPY Makefile /usr/local/src/speck/

RUN make -C /usr/local/src/speck all install

# ============================================================================

FROM debian:forky

# The git dependency is for use in client devcontainers,
# certificates are required for git.
RUN apt update --quiet \
 && apt install --quiet --yes --no-install-recommends ca-certificates git pandoc

COPY --from=build /usr/local/lib/lua/5.4/* /usr/local/lib/lua/5.4/
COPY --from=build /usr/local/share/speck/* /usr/local/share/speck/
COPY --from=build /usr/local/bin/* /usr/local/bin/

ENTRYPOINT ["/usr/local/bin/speck"]

# GitHub actions configure their own working directory,
# this one is for use in devcontainers.
WORKDIR /mnt

# GitHub actions run as root, this user is for devcontainers.
RUN groupadd --gid 1000 debian \
 && useradd --uid 1000 --gid 1000 --create-home debian
