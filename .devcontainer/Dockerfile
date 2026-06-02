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
        pkg-config \
        sudo

# Enable sudo so that we can install the package.
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Install pandoc-crossref.
RUN curl -L -o /tmp/pandoc-crossref.tar.xz https://github.com/lierdakil/pandoc-crossref/releases/download/v0.3.24a/pandoc-crossref-Linux-X64.tar.xz \
 && tar -xf /tmp/pandoc-crossref.tar.xz -C /usr/local/bin pandoc-crossref \
 && rm /tmp/pandoc-crossref.tar.xz

# Create local user.
RUN groupadd --gid 1000 debian \
 && useradd --uid 1000 --gid 1000 --groups sudo --create-home debian
