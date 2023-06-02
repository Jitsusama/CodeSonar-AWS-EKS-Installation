# CodeSonar Installation Stage
ARG BASE_IMAGE
FROM ${BASE_IMAGE} AS codesonar

# Final Installation Stage
FROM ubuntu:22.04 AS final

## Install Sample Project Dependencies
RUN set -x \
 && useradd -mu 1000 ubuntu && chown -R ubuntu /home/ubuntu \
 && export DEBIAN_FRONTEND="noninteractive" \
 && apt-get update --quiet \
 && apt-get install --assume-yes --quiet --no-install-recommends \
    build-essential=12.9ubuntu3 \
 && rm -rf /var/lib/apt/lists/*

## Install & Configure CodeSonar
COPY --from=codesonar /opt/codesonar /opt/codesonar
ENV PATH="/opt/codesonar/codesonar/bin:${PATH}"

## Setup Final Environment
USER ubuntu
WORKDIR /home/ubuntu
HEALTHCHECK NONE
