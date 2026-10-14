FROM ghcr.io/cirruslabs/flutter:3.38.4
RUN apt-get update && apt-get install -y --no-install-recommends \
    clang lld llvm cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
    libsqlite3-dev xvfb xauth imagemagick fonts-noto-cjk python3 \
    && rm -rf /var/lib/apt/lists/*
ENV LIBGL_ALWAYS_SOFTWARE=1
WORKDIR /tmp/app
CMD ["bash", "/source/scripts/linux/run-in-container.sh"]
