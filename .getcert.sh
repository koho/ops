#!/usr/bin/env bash
set -e
set -o pipefail

if [ $# -lt 2 ];
then
  echo "missing arguments"
  exit 1
fi

if [ "$1" == "install" ];
then
  shift
  crontab -l | { cat; echo "1 0 * * * $(realpath $0) $@ 2>/dev/null"; } | crontab -
  exit 0
fi

test -f $2 && OLD=$(sha256sum $2 | cut -d' ' -f1)
IFS='/' read ADDR DOMAIN <<< "$1"
FLAGS="-connect $ADDR"
[ -z "$DOMAIN" ] || FLAGS="$FLAGS -servername $DOMAIN"
CERT=$(openssl s_client -showcerts $FLAGS < /dev/null)
sed -n '/-----BEGIN/,/-----END/p' <<<"$CERT" > $2
NEW=$(sha256sum $2 | cut -d' ' -f1)
shift 2
[ "$OLD" == "$NEW" ] || $@
