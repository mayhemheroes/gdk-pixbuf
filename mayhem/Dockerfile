# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile for gdk-pixbuf — builds on the org C/C++ base. All build/test
# dependencies (glib, libpng, libjpeg, libtiff, meson, ninja, shared-mime-info) come from apt so
# mayhem/build.sh needs no network and no meson subproject fetch (fully air-gapped).
FROM ghcr.io/mayhemheroes/base:20260621

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS
ARG COVERAGE_FLAGS=
ARG MAYHEM_JOBS=

# Build/test deps (as root, pinned to the base's snapshot date for reproducibility when set).
USER root
RUN [ -n "$SOURCE_DATE_EPOCH" ] && repro-sources-list.sh || true ; \
    apt-get update && apt-get install -yq --no-install-recommends \
        meson ninja-build pkg-config \
        libglib2.0-dev libpng-dev libjpeg-dev libtiff-dev \
        zlib1g-dev shared-mime-info \
    && rm -rf /var/lib/apt/lists/*
USER mayhem

WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN bash mayhem/build.sh
RUN bash mayhem/test.sh

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
