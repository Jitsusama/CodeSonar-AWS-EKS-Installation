# Final CodeSonar Client Utilities Stage
FROM ubuntu:22.04 AS codesonar

## Used by curl to Download CodeSonar
ARG PACKAGE_BASEURI
ARG PACKAGE_TOKEN
ARG PACKAGE_CHECKSUM="3707c9c04e5bbdf5dfd0fa6dd467677992c4fb171a930a7b65d8bbf08e4ba67b"

## Download & Install CodeSonar
WORKDIR /opt
ENV PATH="/opt/codesonar/codesonar/bin:${PATH}"
RUN set -x \
 ### Create Unprivileged User Account
 && useradd -mu 1000 ubuntu && chown -R ubuntu /home/ubuntu \
 ### Download CodeSonar Installation
 && export DEBIAN_FRONTEND=noninteractive \
 && apt-get update --quiet \
 && apt-get install --assume-yes --quiet --no-install-recommends \
    curl=7.81.0-1ubuntu1.10 \
    ca-certificates=20211016ubuntu0.22.04.1 \
 && curl -O --header "Private-Token: ${PACKAGE_TOKEN}" \
    ${PACKAGE_BASEURI}/codesonar/7.3p1.20230417/x86_64-pc-linux.tar.gz \
 && echo "${PACKAGE_CHECKSUM} *x86_64-pc-linux.tar.gz" | sha256sum -c \
 && apt-get remove --assume-yes --quiet --auto-remove curl ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 ### Install & Configure CodeSonar (Excluding Hub Install Files)
 && tar zxvf x86_64-pc-linux.tar.gz \
    --exclude codesonar/doc \
    --exclude codesonar/py/hub \
    --exclude codesonar/py/processors \
    --exclude codesonar/src/api/javadoc \
    --exclude codevice \
    --exclude csurf/doc \
    --exclude csurf/src/api/javadoc \
    --exclude csurf/src/feir/api/javadoc \
    --exclude third-party/boost \
    --exclude third-party/jquery \
    --exclude third-party/postgresql \
    --exclude third-party/postgresql-8.3 \
    --exclude third-party/postgresql-8.4 \
    --exclude third-party/postgresql-9.0 \
    --exclude third-party/postgresql-9.1 \
    --exclude third-party/postgresql-9.2 \
    --exclude third-party/postgresql-9.3 \
    --exclude third-party/postgresql-9.6 \
    --exclude third-party/postgresql-12 \
    --exclude third-party/sqlalchemy \
 && rm x86_64-pc-linux.tar.gz \
 && mv codesonar-* codesonar \
 && cd /opt/codesonar \
 && rm UNACCEPTED_LICENSE.txt \
 && touch TELEMETRY_DISABLED \
 && codesonar activate

## Setup Final Environment
USER ubuntu
WORKDIR /home/ubuntu
HEALTHCHECK NONE
