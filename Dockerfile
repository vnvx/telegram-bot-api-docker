# syntax=docker/dockerfile:1.5
# The above enables BuildKit features (named mounts) for this Dockerfile.
###############################################################################
# BUILD STAGE
###############################################################################
FROM debian:bookworm-slim AS builder

# Use bash for better error handling & pipefail
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

WORKDIR /usr/src
ARG BUILD_DEPS="build-essential cmake git gperf libssl-dev zlib1g-dev ca-certificates"
ARG BUILD_CORES=1

# Install build deps using an apt cache mount to speed repeated builds
# Note: requires BuildKit (DOCKER_BUILDKIT=1)
RUN --mount=type=cache,target=/var/cache/apt,id=apt-cache \
    --mount=type=cache,target=/var/cache/apt/archives,id=apt-archives \
    apt-get update && \
    apt-get install -y --no-install-recommends $BUILD_DEPS;

# Shallow clone (faster) and keep recursive submodules; use a short-lived clone to reduce layer size
RUN --mount=type=cache,target=/root/.cache/git \
    git clone --depth 1 --recursive --shallow-submodules "https://github.com/tdlib/telegram-bot-api.git" telegram-bot-api

WORKDIR /usr/src/telegram-bot-api

# Cache the build directory between builds to speed subsequent builds
# (The cache is tied to the mount id: tdlib-build)
RUN --mount=type=cache,target=/usr/src/telegram-bot-api/build,id=tdlib-build \
    cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build --parallel "$BUILD_CORES" --target install

# --- Remove build dependencies to shrink the builder image layer ---
# This purges build-only packages and cleans apt lists & temp files.
# (Safe because build is finished and binary is installed under /usr/local.)
RUN apt-get purge -y $BUILD_DEPS || true && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/src/*
###############################################################################
# FINAL STAGE
###############################################################################
FROM debian:bookworm-slim AS runtime

# create a non-root user to run the binary
RUN groupadd --gid 1000 tbot && \
    useradd --uid 1000 --gid tbot --create-home --home-dir /home/tbot --shell /bin/bash tbot

# install only runtime packages (not -dev packages)
RUN apt-get update && apt-get install -y ca-certificates zlib1g procps && rm -rf /var/lib/apt/lists/*

# copy the built binary from builder
COPY --from=builder /usr/local/bin/telegram-bot-api /usr/local/bin/telegram-bot-api

# set a working dir that the process can write to
RUN mkdir -p /var/lib/telegram-bot-api && chown -R tbot:tbot /var/lib/telegram-bot-api

USER tbot
WORKDIR /var/lib/telegram-bot-api

# expose the default port (configurable when running)
ARG LISTEN_PORT=8081
EXPOSE ${LISTEN_PORT}

# graceful stop signal
STOPSIGNAL SIGTERM

# small healthcheck — adjust path/port/endpoint as appropriate for your app
# "telegram-bot-ap" is correct (pattern that searches for process name longer than 15 characters will result in zero matches)
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD pgrep -x telegram-bot-ap >/dev/null || exit 1

ENTRYPOINT ["telegram-bot-api"]
CMD ["--help"]
