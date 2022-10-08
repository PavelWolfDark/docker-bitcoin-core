#!/bin/sh

set -eu

DISTRO="$(cat /etc/os-release | sed -n 's/^ID=//p')"
BITCOIN_CONFIG='/etc/bitcoin'
BITCOIN_DATA='/var/lib/bitcoin'
BITCOIN_LOGS='/var/log/bitcoin'
BITCOIN_CONFIG_FILE="${BITCOIN_CONFIG}/bitcoin.conf"
BITCOIN_DEBUG_LOG_FILE="${BITCOIN_LOGS}/debug.log"

if [ "$(echo $1 | cut -c1)" = '-' ]; then
  set -- bitcoind "$@"
fi

if [ "$1" = 'bitcoind' ]; then
  mkdir -p \
    "${BITCOIN_CONFIG}" \
    "${BITCOIN_DATA}" \
    "${BITCOIN_LOGS}"
  touch \
    "${BITCOIN_CONFIG_FILE}" \
    "${BITCOIN_DEBUG_LOG_FILE}"
  chown -R bitcoin:bitcoin \
    "${BITCOIN_CONFIG}" \
    "${BITCOIN_DATA}" \
    "${BITCOIN_LOGS}"

  set -- "$@" \
    -conf="${BITCOIN_CONFIG_FILE}" \
    -datadir="${BITCOIN_DATA}" \
    -debuglogfile="${BITCOIN_DEBUG_LOG_FILE}"
fi

case "$1" in
  bitcoind|bitcoin-cli|bitcoin-tx)
    if [ "${DISTRO}" = 'alpine' ]; then
      exec su-exec bitcoin "$@"
    else 
      exec gosu bitcoin "$@"
    fi
  ;;
esac

exec "$@"