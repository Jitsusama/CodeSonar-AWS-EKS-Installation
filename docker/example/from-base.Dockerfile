# Final Installation Stage
ARG BASE_IMAGE
FROM ${BASE_IMAGE} AS final

## Install Sample Project Dependencies
USER root
RUN set -x \
 && export DEBIAN_FRONTEND="noninteractive" \
 && apt-get update --quiet \
 && apt-get install --assume-yes --quiet --no-install-recommends \
    build-essential=12.9ubuntu3 \
 && rm -rf /var/lib/apt/lists/*

## Setup Final Environment
USER ubuntu
WORKDIR /home/ubuntu
HEALTHCHECK NONE
