FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG FLUTTER_REVISION=f6ff1529fd6d8af5f706051d9251ac9231c83407
ARG APPIMAGE_BUILDER_VERSION=1.0.3

ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV TZ=Etc/UTC
ENV FLUTTER_HOME=/opt/flutter
ENV APPIMAGE_BUILDER_VERSION=${APPIMAGE_BUILDER_VERSION}
ENV PATH=/opt/flutter/bin:/root/.local/bin:${PATH}

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    binutils \
    ca-certificates \
    clang \
    cmake \
    coreutils \
    curl \
    desktop-file-utils \
    fakeroot \
    file \
    fuse \
    git \
    libgdk-pixbuf2.0-dev \
    libgtk-3-dev \
    liblzma-dev \
    libmediainfo-dev \
    libmpv-dev \
    libzen-dev \
    ninja-build \
    patchelf \
    pkg-config \
    python3 \
    python3-pip \
    python3-setuptools \
    rsync \
    squashfs-tools \
    strace \
    unzip \
    util-linux \
    xz-utils \
    zip \
    zsync && \
    rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/flutter/flutter.git --branch stable --depth 1 "${FLUTTER_HOME}" && \
    cd "${FLUTTER_HOME}" && \
    git fetch --depth 1 origin "${FLUTTER_REVISION}" && \
    git checkout "${FLUTTER_REVISION}" && \
    flutter --disable-analytics && \
    dart --disable-analytics && \
    flutter config --enable-linux-desktop && \
    flutter precache --linux

RUN python3 -m pip install --no-cache-dir --user "appimage-builder==${APPIMAGE_BUILDER_VERSION}"

WORKDIR /workspace

CMD ["bash"]
