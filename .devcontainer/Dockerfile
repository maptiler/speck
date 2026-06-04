# Use the testing distribution, we need access to the newest version of pandoc.
FROM debian:forky

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
