ARG RUST_IMAGE_TAG=1-slim-trixie
ARG DEBIAN_IMAGE_TAG=trixie-slim

############################################################
# Base image with cargo-chef, to cache the build of the dependencies
FROM rust:${RUST_IMAGE_TAG} AS chef

# jemalloc needs a C toolchain to be built
RUN apt-get update && \
  apt-get install -y --no-install-recommends build-essential && \
  rm -rf /var/lib/apt/lists/*

RUN cargo install cargo-chef --locked

WORKDIR /build

############################################################
# Compute the recipe of the dependencies to build
FROM chef AS planner

COPY . .
RUN cargo chef prepare --recipe-path recipe.json

############################################################
# Builder
FROM chef AS builder

# Build only the dependencies. This layer is cached as long as the recipe, i.e Cargo.toml/Cargo.lock, does not change
COPY --from=planner /build/recipe.json recipe.json
RUN cargo chef cook --release --locked --recipe-path recipe.json

COPY . .
RUN cargo build --release --locked

############################################################
# Final image
FROM debian:${DEBIAN_IMAGE_TAG}

RUN apt-get update && \
  apt-get -y upgrade && \
  rm -rf /var/lib/apt/lists/* && \
  useradd -ms /bin/bash app

COPY --from=builder /build/target/release/blog /usr/local/bin/blog

# One directory per hostname to serve, i.e: public/wstunnel is served for wstunnel.erebe.eu
# --chown is required, as COPY keeps the permissions of the files, which may not be readable by the app user
COPY --chown=app:app public/ /app/public/

USER app
WORKDIR /app
ENV ROOT_DIR=/app/public
ENV HTTP_LISTEN="[::]:8080"
EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/blog"]
