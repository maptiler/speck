# This file describes the image used for the GitHub action.
# It is based on the devcontainer version, but is split into
# two phases to minimize the size of the image.

# ============================================================================

FROM debian:forky AS build

RUN apt update --quiet \
 && apt install --quiet --yes --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        liblua5.4-dev \
        pkg-config

RUN curl -L -o /tmp/pandoc-crossref.tar.xz https://github.com/lierdakil/pandoc-crossref/releases/download/v0.3.24a/pandoc-crossref-Linux-X64.tar.xz \
 && tar -xf /tmp/pandoc-crossref.tar.xz -C /usr/local/bin pandoc-crossref \
 && rm /tmp/pandoc-crossref.tar.xz

COPY src/* /usr/local/src/speck/src/
COPY Makefile /usr/local/src/speck/

RUN make -C /usr/local/src/speck all install

# ============================================================================

FROM debian:forky

RUN apt update --quiet \
 && apt install --quiet --yes --no-install-recommends pandoc
        
COPY --from=build /usr/local/lib/lua/5.4/* /usr/local/lib/lua/5.4/
COPY --from=build /usr/local/share/speck/* /usr/local/share/speck/
COPY --from=build /usr/local/bin/* /usr/local/bin/

ENTRYPOINT ["/usr/local/bin/speck"]

WORKDIR /github/workspace

# For local testing, not used by the action.
RUN groupadd --gid 1000 debian \
 && useradd --uid 1000 --gid 1000 --groups sudo --create-home debian
