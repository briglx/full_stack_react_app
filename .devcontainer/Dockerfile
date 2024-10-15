FROM mcr.microsoft.com/devcontainers/typescript-node:20

RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    shellcheck \
    unzip \
    vim \
    && rm -rf /var/lib/apt/lists/*

# Helpful aliases
RUN echo 'alias ll='"'"'ls $LS_OPTIONS -al'"'"'' >> /etc/bash.bashrc

RUN npm install -g pnpm

# Install additional dependencies if needed
# RUN npm install -g next