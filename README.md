# Docker Bitcoin Core

## Supported versions

- 23.0
- 22.0

## Pull

### Docker Hub

#### Ubuntu

```
docker pull dwreg/bitcoin-core
docker pull dwreg/bitcoin-core:<version>
```

#### Alpine

```
docker pull dwreg/bitcoin-core:alpine
docker pull dwreg/bitcoin-core:<version>-alpine
```

### Darkwolf Registry

#### Ubuntu

```
docker pull registry.darkwolf.cloud/bitcoin-core
docker pull registry.darkwolf.cloud/bitcoin-core:<version>
```

#### Alpine

```
docker pull registry.darkwolf.cloud/bitcoin-core:alpine
docker pull registry.darkwolf.cloud/bitcoin-core:<version>-alpine
```

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
