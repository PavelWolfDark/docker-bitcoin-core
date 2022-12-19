ARG TARGETPLATFORM=linux/amd64
ARG BASE=ubuntu
ARG UBUNTU_VERSION=22.04
ARG ALPINE_VERSION=3.16
ARG BITCOIN_CORE_VERSION=24.0.1

FROM ubuntu:${UBUNTU_VERSION} AS ubuntu

FROM alpine:${ALPINE_VERSION} AS alpine

FROM alpine AS alpine-berkeley-db-4.8.30-build
ENV BERKELEY_DB_VERSION=4.8.30
RUN \
  set -eux \
  && apk add --no-cache \
    autoconf \
    automake \
    build-base 
WORKDIR /src
RUN \
  set -eux \
  && wget -O berkeley-db.tar.gz "https://download.oracle.com/berkeley-db/db-${BERKELEY_DB_VERSION}.tar.gz" \
  && echo 'e0491a07cdb21fb9aa82773bbbedaeb7639cbd0e7f96147ab46141e0045db72a  berkeley-db.tar.gz' | sha256sum -c - \
  && tar -xzvf berkeley-db.tar.gz \
  && mv "db-${BERKELEY_DB_VERSION}" berkeley-db
RUN \
  set -eux \
  && for filename in \
    'config.guess' \
    'config.sub'; do \
      wget -O $filename "https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=${filename};hb=HEAD" \
      && mv $filename berkeley-db/dist/; \
  done \
  && sed -i s/__atomic_compare_exchange/__atomic_compare_exchange_db/g berkeley-db/dbinc/atomic.h
WORKDIR /dist
RUN \
  set -eux \
  && cd /src/berkeley-db/build_unix \
  && ../dist/configure \
    --prefix=/dist \
    --enable-cxx \
    --disable-shared \
    --with-pic \
  && make \
  && make install \
  && rm -rf /dist/docs

FROM scratch AS alpine-berkeley-db-4.8.30-release
COPY --from=alpine-berkeley-db-4.8.30-build /dist /

FROM ubuntu AS ubuntu-bitcoin-core-24.0.1-build
ARG TARGETPLATFORM
ENV BITCOIN_CORE_VERSION=24.0.1
RUN \
  set -eux \
  && apt-get update \
  && apt-get install --no-install-recommends -y \
    ca-certificates \
    wget \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN \
  set -eux \
  && case "${TARGETPLATFORM}" in \
    linux/amd64) \
      target='x86_64-linux-gnu' \
      && sha256='49df6e444515d457ea0b885d66f521f2a26ca92ccf73d5296082e633544253bf' \
      ;; \
    linux/arm64) \
      target='aarch64-linux-gnu' \
      && sha256='0b48b9e69b30037b41a1e6b78fb7cbcc48c7ad627908c99686e81f3802454609' \
      ;; \
    linux/arm/v7) \
      target='arm-linux-gnueabihf' \
      && sha256='37d7660f0277301744e96426bbb001d2206b8d4505385dfdeedf50c09aaaef60' \
      ;; \
    linux/ppc64) \
      target='powerpc64-linux-gnu' \
      && sha256='7590645e8676f8b5fda62dc20174474c4ac8fd0defc83a19ed908ebf2e94dc11' \
      ;; \
    linux/ppc64le) \
      target='powerpc64le-linux-gnu' \
      && sha256='79e89a101f23ff87816675b98769cd1ee91059f95c5277f38f48f21a9f7f8509' \
      ;; \
    linux/riscv64) \
      target='riscv64-linux-gnu' \
      && sha256='6b163cef7de4beb07b8cb3347095e0d76a584019b1891135cd1268a1f05b9d88' \
      ;; \
    *) \
      echo "Target platform '${TARGETPLATFORM}' is not supported." >&2 \
      && exit 1 \
      ;; \
  esac \
  && wget -O bitcoin-core.tar.gz "https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_CORE_VERSION}/bitcoin-${BITCOIN_CORE_VERSION}-${target}.tar.gz" \
  && echo "${sha256} bitcoin-core.tar.gz" | sha256sum -c - \
  && tar -xzvf bitcoin-core.tar.gz \
  && mv "bitcoin-${BITCOIN_CORE_VERSION}" bitcoin-core
  WORKDIR /dist
  RUN \
    set -eux \
    && cp -r \
      /src/bitcoin-core/bin \
      /src/bitcoin-core/lib \
      /src/bitcoin-core/include \
      /src/bitcoin-core/share \
      . \
    && rm -rf \
      bin/bitcoin-qt \
      bin/test_bitcoin \
      share/man/man1/bitcoin-qt.1

FROM scratch AS ubuntu-bitcoin-core-24.0.1-release
COPY --from=ubuntu-bitcoin-core-24.0.1-build /dist /

FROM ubuntu AS ubuntu-bitcoin-core-24.0.1-deploy
ARG UID=1000
ARG GID=1000
RUN \
  set -eux \
  && apt-get update \
  && apt-get install --no-install-recommends -y \
    gosu \
    $( \
      if [[ "${TARGETPLATFORM}" == 'linux/riscv64' ]]; then \
        echo 'libatomic1'; \
      fi \
    ) \
  && rm -rf /var/lib/apt/lists/*
COPY --from=ubuntu-bitcoin-core-24.0.1-release / /usr/
RUN \
  set -eux \
  && groupadd -g "${GID}" bitcoin \
  && useradd -u "${UID}" -g bitcoin bitcoin
COPY bitcoin.conf /etc/bitcoin/
VOLUME \
  /etc/bitcoin \
  /var/lib/bitcoin \
  /var/log/bitcoin
EXPOSE \
  8332 \
  8333 \
  18332 \
  18333 \
  18443 \
  18444 \
  38332 \
  38333
COPY --chmod=700 docker-entrypoint.sh /usr/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]
CMD ["bitcoind"]

FROM alpine AS alpine-bitcoin-core-24.0.1-build
ENV BITCOIN_CORE_VERSION=24.0.1
RUN \
  set -eux \
  && apk add --no-cache \
    autoconf \
    automake \
    build-base \
    libtool \
    boost-dev \
    libevent-dev \
    chrpath \
    zeromq-dev
WORKDIR /src
COPY --from=alpine-berkeley-db-4.8.30-release / berkeley-db
RUN \
  set -eux \
  && wget -O bitcoin-core.tar.gz "https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_CORE_VERSION}/bitcoin-${BITCOIN_CORE_VERSION}.tar.gz" \
  && echo '12d4ad6dfab4767d460d73307e56d13c72997e114fad4f274650f95560f5f2ff  bitcoin-core.tar.gz' | sha256sum -c - \
  && tar -xzvf bitcoin-core.tar.gz \
  && mv "bitcoin-${BITCOIN_CORE_VERSION}" bitcoin-core
WORKDIR /dist
RUN \
  set -eux \
  && cd /src/bitcoin-core \
  && ./autogen.sh \
  && ./configure \
    LDFLAGS=-L/src/berkeley-db/lib \
    CPPFLAGS=-I/src/berkeley-db/include \
    --prefix=/dist \
    --disable-tests \
    --disable-bench \
    --disable-ccache \
    --with-utils \
    --with-libs \
    --with-daemon \
    --without-gui \
  && make \
  && make install \
  && strip \
    /dist/bin/bitcoind \
    /dist/bin/bitcoin-cli \
    /dist/bin/bitcoin-tx \
    /dist/bin/bitcoin-util \
    /dist/bin/bitcoin-wallet \
    /dist/lib/libbitcoinconsensus.a \
    /dist/lib/libbitcoinconsensus.so.0.0.0

FROM scratch AS alpine-bitcoin-core-24.0.1-release
COPY --from=alpine-bitcoin-core-24.0.1-build /dist /

FROM alpine AS alpine-bitcoin-core-24.0.1-deploy
ARG UID=1000
ARG GID=1000
RUN \
  set -eux \
  && apk add --no-cache \
    boost-system \
    boost-filesystem \
    boost-thread \
    libevent \
    zeromq \
    su-exec
COPY --from=alpine-bitcoin-core-24.0.1-release / /usr/
RUN \
  set -eux \
  && addgroup -g "${GID}" bitcoin \
  && adduser -u "${UID}" -G bitcoin -D bitcoin
COPY bitcoin.conf /etc/bitcoin/
VOLUME \
  /etc/bitcoin \
  /var/lib/bitcoin \
  /var/log/bitcoin
EXPOSE \
  8332 \
  8333 \
  18332 \
  18333 \
  18443 \
  18444 \
  38332 \
  38333
COPY --chmod=700 docker-entrypoint.sh /usr/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]
CMD ["bitcoind"]

FROM ubuntu AS ubuntu-bitcoin-core-24.0-build
ARG TARGETPLATFORM
ENV BITCOIN_CORE_VERSION=24.0
RUN \
  set -eux \
  && apt-get update \
  && apt-get install --no-install-recommends -y \
    ca-certificates \
    wget \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN \
  set -eux \
  && case "${TARGETPLATFORM}" in \
    linux/amd64) \
      target='x86_64-linux-gnu' \
      && sha256='fb86cf6af7a10bc5f3ae6cd6a5b0348854e1462102fe71e755d30b51b6e317d1' \
      ;; \
    linux/arm64) \
      target='aarch64-linux-gnu' \
      && sha256='904e103f08f776d03935118568411724f9e070e0e888e52c9e5692308fa47d49' \
      ;; \
    linux/arm/v7) \
      target='arm-linux-gnueabihf' \
      && sha256='806f822a0498bb4f93ba13d6370e544c2344a768cd45c5a24cab1e7e87930204' \
      ;; \
    linux/ppc64) \
      target='powerpc64-linux-gnu' \
      && sha256='aa2e29abd43223054031a2667fdc15934ae3dc294c5aaf2959ffc8d33cc2c722' \
      ;; \
    linux/ppc64le) \
      target='powerpc64le-linux-gnu' \
      && sha256='f7a0c4a0d24f65ebcbfe4b6d8033408340e823e0131d4fcccc86296280bbe3c6' \
      ;; \
    linux/riscv64) \
      target='riscv64-linux-gnu' \
      && sha256='3c5366ab68cf9c3f24d6b97a2afca96e1ee28d915b7f32d92c60bf6e7da3dee6' \
      ;; \
    *) \
      echo "Target platform '${TARGETPLATFORM}' is not supported." >&2 \
      && exit 1 \
      ;; \
  esac \
  && wget -O bitcoin-core.tar.gz "https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_CORE_VERSION}/bitcoin-${BITCOIN_CORE_VERSION}-${target}.tar.gz" \
  && echo "${sha256} bitcoin-core.tar.gz" | sha256sum -c - \
  && tar -xzvf bitcoin-core.tar.gz \
  && mv "bitcoin-${BITCOIN_CORE_VERSION}" bitcoin-core
  WORKDIR /dist
  RUN \
    set -eux \
    && cp -r \
      /src/bitcoin-core/bin \
      /src/bitcoin-core/lib \
      /src/bitcoin-core/include \
      /src/bitcoin-core/share \
      . \
    && rm -rf \
      bin/bitcoin-qt \
      bin/test_bitcoin \
      share/man/man1/bitcoin-qt.1

FROM scratch AS ubuntu-bitcoin-core-24.0-release
COPY --from=ubuntu-bitcoin-core-24.0-build /dist /

FROM ubuntu AS ubuntu-bitcoin-core-24.0-deploy
ARG UID=1000
ARG GID=1000
RUN \
  set -eux \
  && apt-get update \
  && apt-get install --no-install-recommends -y \
    gosu \
    $( \
      if [[ "${TARGETPLATFORM}" == 'linux/riscv64' ]]; then \
        echo 'libatomic1'; \
      fi \
    ) \
  && rm -rf /var/lib/apt/lists/*
COPY --from=ubuntu-bitcoin-core-24.0-release / /usr/
RUN \
  set -eux \
  && groupadd -g "${GID}" bitcoin \
  && useradd -u "${UID}" -g bitcoin bitcoin
COPY bitcoin.conf /etc/bitcoin/
VOLUME \
  /etc/bitcoin \
  /var/lib/bitcoin \
  /var/log/bitcoin
EXPOSE \
  8332 \
  8333 \
  18332 \
  18333 \
  18443 \
  18444 \
  38332 \
  38333
COPY --chmod=700 docker-entrypoint.sh /usr/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]
CMD ["bitcoind"]

FROM alpine AS alpine-bitcoin-core-24.0-build
ENV BITCOIN_CORE_VERSION=24.0
RUN \
  set -eux \
  && apk add --no-cache \
    autoconf \
    automake \
    build-base \
    libtool \
    boost-dev \
    libevent-dev \
    chrpath \
    zeromq-dev
WORKDIR /src
COPY --from=alpine-berkeley-db-4.8.30-release / berkeley-db
RUN \
  set -eux \
  && wget -O bitcoin-core.tar.gz "https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_CORE_VERSION}/bitcoin-${BITCOIN_CORE_VERSION}.tar.gz" \
  && echo '9cfa4a9f4acb5093e85b8b528392f0f05067f3f8fafacd4dcfe8a396158fd9f4  bitcoin-core.tar.gz' | sha256sum -c - \
  && tar -xzvf bitcoin-core.tar.gz \
  && mv "bitcoin-${BITCOIN_CORE_VERSION}" bitcoin-core
WORKDIR /dist
RUN \
  set -eux \
  && cd /src/bitcoin-core \
  && ./autogen.sh \
  && ./configure \
    LDFLAGS=-L/src/berkeley-db/lib \
    CPPFLAGS=-I/src/berkeley-db/include \
    --prefix=/dist \
    --disable-tests \
    --disable-bench \
    --disable-ccache \
    --with-utils \
    --with-libs \
    --with-daemon \
    --without-gui \
  && make \
  && make install \
  && strip \
    /dist/bin/bitcoind \
    /dist/bin/bitcoin-cli \
    /dist/bin/bitcoin-tx \
    /dist/bin/bitcoin-util \
    /dist/bin/bitcoin-wallet \
    /dist/lib/libbitcoinconsensus.a \
    /dist/lib/libbitcoinconsensus.so.0.0.0

FROM scratch AS alpine-bitcoin-core-24.0-release
COPY --from=alpine-bitcoin-core-24.0-build /dist /

FROM alpine AS alpine-bitcoin-core-24.0-deploy
ARG UID=1000
ARG GID=1000
RUN \
  set -eux \
  && apk add --no-cache \
    boost-system \
    boost-filesystem \
    boost-thread \
    libevent \
    zeromq \
    su-exec
COPY --from=alpine-bitcoin-core-24.0-release / /usr/
RUN \
  set -eux \
  && addgroup -g "${GID}" bitcoin \
  && adduser -u "${UID}" -G bitcoin -D bitcoin
COPY bitcoin.conf /etc/bitcoin/
VOLUME \
  /etc/bitcoin \
  /var/lib/bitcoin \
  /var/log/bitcoin
EXPOSE \
  8332 \
  8333 \
  18332 \
  18333 \
  18443 \
  18444 \
  38332 \
  38333
COPY --chmod=700 docker-entrypoint.sh /usr/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]
CMD ["bitcoind"]

FROM ubuntu AS ubuntu-bitcoin-core-23.0-build
ARG TARGETPLATFORM
ENV BITCOIN_CORE_VERSION=23.0
RUN \
  set -eux \
  && apt-get update \
  && apt-get install --no-install-recommends -y \
    ca-certificates \
    wget \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN \
  set -eux \
  && case "${TARGETPLATFORM}" in \
    linux/amd64) \
      target='x86_64-linux-gnu' \
      && sha256='2cca490c1f2842884a3c5b0606f179f9f937177da4eadd628e3f7fd7e25d26d0' \
      ;; \
    linux/arm64) \
      target='aarch64-linux-gnu' \
      && sha256='06f4c78271a77752ba5990d60d81b1751507f77efda1e5981b4e92fd4d9969fb' \
      ;; \
    linux/arm/v7) \
      target='arm-linux-gnueabihf' \
      && sha256='952c574366aff76f6d6ad1c9ee45a361d64fa04155e973e926dfe7e26f9703a3' \
      ;; \
    linux/ppc64) \
      target='powerpc64-linux-gnu' \
      && sha256='2caa5898399e415f61d9af80a366a3008e5856efa15aaff74b88acf429674c99' \
      ;; \
    linux/ppc64le) \
      target='powerpc64le-linux-gnu' \
      && sha256='217dd0469d0f4962d22818c368358575f6a0abcba8804807bb75325eb2f28b19' \
      ;; \
    linux/riscv64) \
      target='riscv64-linux-gnu' \
      && sha256='078f96b1e92895009c798ab827fb3fde5f6719eee886bd0c0e93acab18ea4865' \
      ;; \
    *) \
      echo "Target platform '${TARGETPLATFORM}' is not supported." >&2 \
      && exit 1 \
      ;; \
  esac \
  && wget -O bitcoin-core.tar.gz "https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_CORE_VERSION}/bitcoin-${BITCOIN_CORE_VERSION}-${target}.tar.gz" \
  && echo "${sha256} bitcoin-core.tar.gz" | sha256sum -c - \
  && tar -xzvf bitcoin-core.tar.gz \
  && mv "bitcoin-${BITCOIN_CORE_VERSION}" bitcoin-core
  WORKDIR /dist
  RUN \
    set -eux \
    && cp -r \
      /src/bitcoin-core/bin \
      /src/bitcoin-core/lib \
      /src/bitcoin-core/include \
      /src/bitcoin-core/share \
      . \
    && rm -rf \
      bin/bitcoin-qt \
      bin/test_bitcoin \
      share/man/man1/bitcoin-qt.1

FROM scratch AS ubuntu-bitcoin-core-23.0-release
COPY --from=ubuntu-bitcoin-core-23.0-build /dist /

FROM ubuntu AS ubuntu-bitcoin-core-23.0-deploy
ARG UID=1000
ARG GID=1000
RUN \
  set -eux \
  && apt-get update \
  && apt-get install --no-install-recommends -y \
    gosu \
    $( \
      if [[ "${TARGETPLATFORM}" == 'linux/riscv64' ]]; then \
        echo 'libatomic1'; \
      fi \
    ) \
  && rm -rf /var/lib/apt/lists/*
COPY --from=ubuntu-bitcoin-core-23.0-release / /usr/
RUN \
  set -eux \
  && groupadd -g "${GID}" bitcoin \
  && useradd -u "${UID}" -g bitcoin bitcoin
COPY bitcoin.conf /etc/bitcoin/
VOLUME \
  /etc/bitcoin \
  /var/lib/bitcoin \
  /var/log/bitcoin
EXPOSE \
  8332 \
  8333 \
  18332 \
  18333 \
  18443 \
  18444 \
  38332 \
  38333
COPY --chmod=700 docker-entrypoint.sh /usr/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]
CMD ["bitcoind"]

FROM alpine AS alpine-bitcoin-core-23.0-build
ENV BITCOIN_CORE_VERSION=23.0
RUN \
  set -eux \
  && apk add --no-cache \
    autoconf \
    automake \
    build-base \
    libtool \
    boost-dev \
    libevent-dev \
    chrpath \
    zeromq-dev
WORKDIR /src
COPY --from=alpine-berkeley-db-4.8.30-release / berkeley-db
RUN \
  set -eux \
  && wget -O bitcoin-core.tar.gz "https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_CORE_VERSION}/bitcoin-${BITCOIN_CORE_VERSION}.tar.gz" \
  && echo '26748bf49d6d6b4014d0fedccac46bf2bcca42e9d34b3acfd9e3467c415acc05  bitcoin-core.tar.gz' | sha256sum -c - \
  && tar -xzvf bitcoin-core.tar.gz \
  && mv "bitcoin-${BITCOIN_CORE_VERSION}" bitcoin-core
WORKDIR /dist
RUN \
  set -eux \
  && cd /src/bitcoin-core \
  && ./autogen.sh \
  && ./configure \
    LDFLAGS=-L/src/berkeley-db/lib \
    CPPFLAGS=-I/src/berkeley-db/include \
    --prefix=/dist \
    --disable-tests \
    --disable-bench \
    --disable-ccache \
    --with-utils \
    --with-libs \
    --with-daemon \
    --without-gui \
  && make \
  && make install \
  && strip \
    /dist/bin/bitcoind \
    /dist/bin/bitcoin-cli \
    /dist/bin/bitcoin-tx \
    /dist/bin/bitcoin-util \
    /dist/bin/bitcoin-wallet \
    /dist/lib/libbitcoinconsensus.a \
    /dist/lib/libbitcoinconsensus.so.0.0.0

FROM scratch AS alpine-bitcoin-core-23.0-release
COPY --from=alpine-bitcoin-core-23.0-build /dist /

FROM alpine AS alpine-bitcoin-core-23.0-deploy
ARG UID=1000
ARG GID=1000
RUN \
  set -eux \
  && apk add --no-cache \
    boost-system \
    boost-filesystem \
    boost-thread \
    libevent \
    zeromq \
    su-exec
COPY --from=alpine-bitcoin-core-23.0-release / /usr/
RUN \
  set -eux \
  && addgroup -g "${GID}" bitcoin \
  && adduser -u "${UID}" -G bitcoin -D bitcoin
COPY bitcoin.conf /etc/bitcoin/
VOLUME \
  /etc/bitcoin \
  /var/lib/bitcoin \
  /var/log/bitcoin
EXPOSE \
  8332 \
  8333 \
  18332 \
  18333 \
  18443 \
  18444 \
  38332 \
  38333
COPY --chmod=700 docker-entrypoint.sh /usr/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]
CMD ["bitcoind"]

FROM ubuntu AS ubuntu-bitcoin-core-22.1-build
ARG TARGETPLATFORM
ENV BITCOIN_CORE_VERSION=22.1
RUN \
  set -eux \
  && apt-get update \
  && apt-get install --no-install-recommends -y \
    ca-certificates \
    wget \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN \
  set -eux \
  && case "${TARGETPLATFORM}" in \
    linux/amd64) \
      target='x86_64-linux-gnu' \
      && sha256='107e6a8d1f545de1299cbf93dfd7d41c9d67956f1ac9c910d7eaed1e363cfa2c' \
      ;; \
    linux/arm64) \
      target='aarch64-linux-gnu' \
      && sha256='a0dcdd1eb422ba8d0f409ebe909a40f5349b405e31231312f15b12fd2e9b6153' \
      ;; \
    linux/arm/v7) \
      target='arm-linux-gnueabihf' \
      && sha256='7046aa71c3f8247205ebbb838c8f0217552a499aac6281cea7f4747f4e42c2e9' \
      ;; \
    linux/ppc64) \
      target='powerpc64-linux-gnu' \
      && sha256='bf6998392b34882c5067e758c19e2d0d0b747ff2090b4bc039fcb382a138d4ba' \
      ;; \
    linux/ppc64le) \
      target='powerpc64le-linux-gnu' \
      && sha256='4d14aa4a73d3f777e40568ea81722413f75f735cefad99d46d81cd2c3fd6656c' \
      ;; \
    linux/riscv64) \
      target='riscv64-linux-gnu' \
      && sha256='0e9598ecf04e5c887391615af130285bdf30fd7443a301e81a079499379415e9' \
      ;; \
    *) \
      echo "Target platform '${TARGETPLATFORM}' is not supported." >&2 \
      && exit 1 \
      ;; \
    esac \
    && wget -O bitcoin-core.tar.gz "https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_CORE_VERSION}/bitcoin-${BITCOIN_CORE_VERSION}-${target}.tar.gz" \
    && echo "${sha256} bitcoin-core.tar.gz" | sha256sum -c - \
    && tar -xzvf bitcoin-core.tar.gz \
    && mv "bitcoin-${BITCOIN_CORE_VERSION}" bitcoin-core
WORKDIR /dist
RUN \
  set -eux \
  && cp -r \
    /src/bitcoin-core/bin \
    /src/bitcoin-core/lib \
    /src/bitcoin-core/include \
    /src/bitcoin-core/share \
    . \
  && rm -rf \
    bin/bitcoin-qt \
    bin/test_bitcoin \
    share/man/man1/bitcoin-qt.1

FROM scratch AS ubuntu-bitcoin-core-22.1-release
COPY --from=ubuntu-bitcoin-core-22.1-build /dist /

FROM ubuntu AS ubuntu-bitcoin-core-22.1-deploy
ARG UID=1000
ARG GID=1000
RUN \
  set -eux \
  && apt-get update \
  && apt-get install --no-install-recommends -y \
    gosu \
    $( \
      if [[ "${TARGETPLATFORM}" == 'linux/riscv64' ]]; then \
        echo 'libatomic1'; \
      fi \
    ) \
  && rm -rf /var/lib/apt/lists/*
COPY --from=ubuntu-bitcoin-core-22.1-release / /usr/
RUN \
  set -eux \
  && groupadd -g "${GID}" bitcoin \
  && useradd -u "${UID}" -g bitcoin bitcoin
COPY bitcoin.conf /etc/bitcoin/
VOLUME \
  /etc/bitcoin \
  /var/lib/bitcoin \
  /var/log/bitcoin
EXPOSE \
  8332 \
  8333 \
  18332 \
  18333 \
  18443 \
  18444 \
  38332 \
  38333
COPY --chmod=700 docker-entrypoint.sh /usr/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]
CMD ["bitcoind"]

FROM alpine AS alpine-bitcoin-core-22.1-build
ENV BITCOIN_CORE_VERSION=22.1
RUN \
  set -eux \
  && apk add --no-cache \
    autoconf \
    automake \
    build-base \
    libtool \
    boost-dev \
    libevent-dev \
    chrpath \
    zeromq-dev
WORKDIR /src
COPY --from=alpine-berkeley-db-4.8.30-release / berkeley-db
RUN \
  set -eux \
  && wget -O bitcoin-core.tar.gz "https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_CORE_VERSION}/bitcoin-${BITCOIN_CORE_VERSION}.tar.gz" \
  && echo '1eebf3cc06feee4b5bdd35cf28e15f567dffede95749b730495daa4577125315  bitcoin-core.tar.gz' | sha256sum -c - \
  && tar -xzvf bitcoin-core.tar.gz \
  && mv "bitcoin-${BITCOIN_CORE_VERSION}" bitcoin-core
WORKDIR /dist
RUN \
  set -eux \
  && cd /src/bitcoin-core \
  && ./autogen.sh \
  && ./configure \
    LDFLAGS=-L/src/berkeley-db/lib \
    CPPFLAGS=-I/src/berkeley-db/include \
    --prefix=/dist \
    --disable-tests \
    --disable-bench \
    --disable-ccache \
    --with-utils \
    --with-libs \
    --with-daemon \
    --without-gui \
  && make \
  && make install \
  && strip \
    /dist/bin/bitcoind \
    /dist/bin/bitcoin-cli \
    /dist/bin/bitcoin-tx \
    /dist/bin/bitcoin-util \
    /dist/bin/bitcoin-wallet \
    /dist/lib/libbitcoinconsensus.a \
    /dist/lib/libbitcoinconsensus.so.0.0.0

FROM scratch AS alpine-bitcoin-core-22.1-release
COPY --from=alpine-bitcoin-core-22.1-build /dist /

FROM alpine AS alpine-bitcoin-core-22.1-deploy
ARG UID=1000
ARG GID=1000
RUN \
  set -eux \
  && apk add --no-cache \
    boost-system \
    boost-filesystem \
    boost-thread \
    libevent \
    zeromq \
    su-exec
COPY --from=alpine-bitcoin-core-22.1-release / /usr/
RUN \
  set -eux \
  && addgroup -g "${GID}" bitcoin \
  && adduser -u "${UID}" -G bitcoin -D bitcoin
COPY bitcoin.conf /etc/bitcoin/
VOLUME \
  /etc/bitcoin \
  /var/lib/bitcoin \
  /var/log/bitcoin
EXPOSE \
  8332 \
  8333 \
  18332 \
  18333 \
  18443 \
  18444 \
  38332 \
  38333
COPY --chmod=700 docker-entrypoint.sh /usr/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]
CMD ["bitcoind"]

FROM ubuntu AS ubuntu-bitcoin-core-22.0-build
ARG TARGETPLATFORM
ENV BITCOIN_CORE_VERSION=22.0
RUN \
  set -eux \
  && apt-get update \
  && apt-get install --no-install-recommends -y \
    ca-certificates \
    wget \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN \
  set -eux \
  && case "${TARGETPLATFORM}" in \
    linux/amd64) \
      target='x86_64-linux-gnu' \
      && sha256='59ebd25dd82a51638b7a6bb914586201e67db67b919b2a1ff08925a7936d1b16' \
      ;; \
    linux/arm64) \
      target='aarch64-linux-gnu' \
      && sha256='ac718fed08570a81b3587587872ad85a25173afa5f9fbbd0c03ba4d1714cfa3e' \
      ;; \
    linux/arm/v7) \
      target='arm-linux-gnueabihf' \
      && sha256='b8713c6c5f03f5258b54e9f436e2ed6d85449aa24c2c9972f91963d413e86311' \
      ;; \
    linux/ppc64) \
      target='powerpc64-linux-gnu' \
      && sha256='2cca5f99007d060aca9d8c7cbd035dfe2f040dd8200b210ce32cdf858479f70d' \
      ;; \
    linux/ppc64le) \
      target='powerpc64le-linux-gnu' \
      && sha256='91b1e012975c5a363b5b5fcc81b5b7495e86ff703ec8262d4b9afcfec633c30d' \
      ;; \
    linux/riscv64) \
      target='riscv64-linux-gnu' \
      && sha256='9cc3a62c469fe57e11485fdd32c916f10ce7a2899299855a2e479256ff49ff3c' \
      ;; \
    *) \
      echo "Target platform '${TARGETPLATFORM}' is not supported." >&2 \
      && exit 1 \
      ;; \
    esac \
    && wget -O bitcoin-core.tar.gz "https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_CORE_VERSION}/bitcoin-${BITCOIN_CORE_VERSION}-${target}.tar.gz" \
    && echo "${sha256} bitcoin-core.tar.gz" | sha256sum -c - \
    && tar -xzvf bitcoin-core.tar.gz \
    && mv "bitcoin-${BITCOIN_CORE_VERSION}" bitcoin-core
WORKDIR /dist
RUN \
  set -eux \
  && cp -r \
    /src/bitcoin-core/bin \
    /src/bitcoin-core/lib \
    /src/bitcoin-core/include \
    /src/bitcoin-core/share \
    . \
  && rm -rf \
    bin/bitcoin-qt \
    bin/test_bitcoin \
    share/man/man1/bitcoin-qt.1

FROM scratch AS ubuntu-bitcoin-core-22.0-release
COPY --from=ubuntu-bitcoin-core-22.0-build /dist /

FROM ubuntu AS ubuntu-bitcoin-core-22.0-deploy
ARG UID=1000
ARG GID=1000
RUN \
  set -eux \
  && apt-get update \
  && apt-get install --no-install-recommends -y \
    gosu \
    $( \
      if [[ "${TARGETPLATFORM}" == 'linux/riscv64' ]]; then \
        echo 'libatomic1'; \
      fi \
    ) \
  && rm -rf /var/lib/apt/lists/*
COPY --from=ubuntu-bitcoin-core-22.0-release / /usr/
RUN \
  set -eux \
  && groupadd -g "${GID}" bitcoin \
  && useradd -u "${UID}" -g bitcoin bitcoin
COPY bitcoin.conf /etc/bitcoin/
VOLUME \
  /etc/bitcoin \
  /var/lib/bitcoin \
  /var/log/bitcoin
EXPOSE \
  8332 \
  8333 \
  18332 \
  18333 \
  18443 \
  18444 \
  38332 \
  38333
COPY --chmod=700 docker-entrypoint.sh /usr/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]
CMD ["bitcoind"]

FROM alpine AS alpine-bitcoin-core-22.0-build
ENV BITCOIN_CORE_VERSION=22.0
RUN \
  set -eux \
  && apk add --no-cache \
    autoconf \
    automake \
    build-base \
    libtool \
    boost-dev \
    libevent-dev \
    chrpath \
    zeromq-dev
WORKDIR /src
COPY --from=alpine-berkeley-db-4.8.30-release / berkeley-db
RUN \
  set -eux \
  && wget -O bitcoin-core.tar.gz "https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_CORE_VERSION}/bitcoin-${BITCOIN_CORE_VERSION}.tar.gz" \
  && echo 'd0e9d089b57048b1555efa7cd5a63a7ed042482045f6f33402b1df425bf9613b  bitcoin-core.tar.gz' | sha256sum -c - \
  && tar -xzvf bitcoin-core.tar.gz \
  && mv "bitcoin-${BITCOIN_CORE_VERSION}" bitcoin-core
WORKDIR /dist
RUN \
  set -eux \
  && cd /src/bitcoin-core \
  && ./autogen.sh \
  && ./configure \
    LDFLAGS=-L/src/berkeley-db/lib \
    CPPFLAGS=-I/src/berkeley-db/include \
    --prefix=/dist \
    --disable-tests \
    --disable-bench \
    --disable-ccache \
    --with-utils \
    --with-libs \
    --with-daemon \
    --without-gui \
  && make \
  && make install \
  && strip \
    /dist/bin/bitcoind \
    /dist/bin/bitcoin-cli \
    /dist/bin/bitcoin-tx \
    /dist/bin/bitcoin-util \
    /dist/bin/bitcoin-wallet \
    /dist/lib/libbitcoinconsensus.a \
    /dist/lib/libbitcoinconsensus.so.0.0.0

FROM scratch AS alpine-bitcoin-core-22.0-release
COPY --from=alpine-bitcoin-core-22.0-build /dist /

FROM alpine AS alpine-bitcoin-core-22.0-deploy
ARG UID=1000
ARG GID=1000
RUN \
  set -eux \
  && apk add --no-cache \
    boost-system \
    boost-filesystem \
    boost-thread \
    libevent \
    zeromq \
    su-exec
COPY --from=alpine-bitcoin-core-22.0-release / /usr/
RUN \
  set -eux \
  && addgroup -g "${GID}" bitcoin \
  && adduser -u "${UID}" -G bitcoin -D bitcoin
COPY bitcoin.conf /etc/bitcoin/
VOLUME \
  /etc/bitcoin \
  /var/lib/bitcoin \
  /var/log/bitcoin
EXPOSE \
  8332 \
  8333 \
  18332 \
  18333 \
  18443 \
  18444 \
  38332 \
  38333
COPY --chmod=700 docker-entrypoint.sh /usr/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]
CMD ["bitcoind"]

FROM ${BASE}-bitcoin-core-${BITCOIN_CORE_VERSION}-build AS build
LABEL maintainer="Pavel Wolf <cyberviking@darkwolf.team>"

FROM ${BASE}-bitcoin-core-${BITCOIN_CORE_VERSION}-release AS release
LABEL maintainer="Pavel Wolf <cyberviking@darkwolf.team>"

FROM ${BASE}-bitcoin-core-${BITCOIN_CORE_VERSION}-deploy AS deploy
LABEL maintainer="Pavel Wolf <cyberviking@darkwolf.team>"