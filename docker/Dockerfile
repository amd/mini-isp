# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

###############################################################################
## Build Verible                                                             ##
###############################################################################
FROM ubuntu:26.04 AS build-verible

ARG DEBIAN_FRONTEND=noninteractive
ARG VERIBLE_VERSION=v0.0-4051-g9fdb4057

ENV TZ=Europe/Berlin

RUN apt-get update; apt-get --no-install-recommends -y install \
        build-essential \
        ca-certificates \
        clang \
        curl \
        git \
        python3 \
        wget \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Bazelisk
RUN wget -q https://github.com/bazelbuild/bazelisk/releases/download/v1.19.0/bazelisk-linux-amd64 -O /usr/local/bin/bazel && chmod a+rx /usr/local/bin/bazel && /usr/local/bin/bazel --version

# Build Verible from source
RUN git clone --recurse-submodules --branch "$VERIBLE_VERSION" --depth 1 https://github.com/chipsalliance/verible.git \
    && cd verible \
    && bazel build -c opt :install-binaries \
    && .github/bin/simple-install.sh /tmp/verible

###############################################################################
## Build Verilator                                                           ##
###############################################################################
FROM ubuntu:26.04 AS build-verilator

ARG DEBIAN_FRONTEND=noninteractive

ARG VERILATOR_VERSION=v5.046

ENV TZ=Europe/Berlin

RUN apt-get update; apt-get --no-install-recommends -y install \
        autoconf \
        bison \
        build-essential \
        ca-certificates \
        ccache \
        curl \
        flex \
        g++ \
        git \
        help2man \
        libfl2 \
        libfl-dev \
        libgoogle-perftools-dev \
        mold \
        numactl \
        perl \
        perl-doc \
        python3 \
        zlib1g \
        zlib1g-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# build verilator from source
RUN git clone --branch "$VERILATOR_VERSION" --depth 1 https://github.com/verilator/verilator \
    && cd verilator \
    && autoconf \
    && ./configure \
    && make -j "$(nproc)" \
    && make DESTDIR=/tmp/verilator install

###############################################################################
## Final image                                                               ##
###############################################################################
FROM ubuntu:26.04

ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

ARG DEBIAN_FRONTEND=noninteractive

ENV TZ=Europe/Berlin
ENV TERM=xterm-256color

# Install basic dependencies
RUN apt-get update; apt-get --no-install-recommends -y install \
        build-essential \
        ca-certificates \
        ccache \
        curl \
        g++ \
        git \
        gosu \
        help2man \
        libfl2 \
        libfl-dev \
        libgoogle-perftools-dev \
        locales \
        make \
        mold \
        numactl \
        openssh-client \
        perl \
        perl-doc \
        python3 \
        python3-dev \
        python3-pip \
        python-is-python3 \
        sudo \
        zlib1g \
        zlib1g-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# remove default user and add vscode user
RUN userdel -r ubuntu || true \
    && groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -s /bin/bash -m $USERNAME \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# Install Verible
COPY --from=build-verible /tmp/verible /usr/local/bin

# Install Verilator
COPY --from=build-verilator /tmp/verilator /

# Install uv
COPY --from=ghcr.io/astral-sh/uv:0.10.7 /uv /uvx /bin/

# set locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Change user and create working directory
USER vscode
RUN gosu mkdir -p /workspaces \
    && gosu chown vscode:vscode /workspaces
WORKDIR /workspaces

# Install dependencies
COPY pyproject.toml uv.lock /workspaces/

ENV UV_PROJECT_ENVIRONMENT="/workspaces/.venv"
RUN uv sync --frozen --no-install-project \
    && rm /workspaces/pyproject.toml /workspaces/uv.lock

# set colorful prompt
RUN echo "PS1='\e[92m\u\e[0m@\e[94m\h\e[0m:\e[35m\w\e[0m# '" >> ~/.bashrc
