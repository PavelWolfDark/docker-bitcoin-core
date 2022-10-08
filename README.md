# Docker Bitcoin Core

## Build

### Ubuntu

```
docker buildx build \
  --build-arg BASE=ubuntu \
  --build-arg UBUNTU_VERSION=<version> \
  --build-arg BITCOIN_CORE_VERSION=<version> \
  --build-arg UID=<uid> \
  --build-arg GID=<gid> \
  --target deploy \
  -t bitcoin-core:<version> .
```

### Alpine

```
docker buildx build \
  --build-arg BASE=alpine \
  --build-arg ALPINE_VERSION=<version> \
  --build-arg BITCOIN_CORE_VERSION=<version> \
  --build-arg UID=<uid> \
  --build-arg GID=<gid> \
  --target deploy \
  -t bitcoin-core:<version>-alpine .
```
