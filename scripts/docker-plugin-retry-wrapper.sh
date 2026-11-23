#!/bin/bash
# docker-plugin-retry-wrapper.sh
#
# Install as /usr/local/bin/docker on slow VMs (for example VirtualBox running on
# top of Hyper-V / VBS). sudo's secure_path puts /usr/local/bin before /usr/bin,
# so the Kasm installer picks this up automatically.
#
# Why: Docker waits only a few seconds for a managed plugin to open its socket.
# Kasm's plugins can start slower than that on a slow VM, so Docker marks them
# failed ("kasmlogger.sock: no such file or directory",
# "kasmnetwork.sock: connection refused") and the installer aborts.
#
# What it changes:
#   docker plugin install ...  -> installs with --disable, then retries enable
#   docker plugin enable NAME  -> retries enable up to 12 times (5 s apart)
# Every other command is passed unchanged to the real docker binary.

REAL=/usr/bin/docker

if [ ! -x "$REAL" ]; then
  echo "docker-plugin-retry-wrapper: real docker not found at $REAL (install Docker first)" >&2
  exit 127
fi

is_enabled() {
  [ "$($REAL plugin inspect -f '{{.Enabled}}' "$1" 2>/dev/null)" = "true" ]
}

enable_retry() {
  local name="$1"
  for n in $(seq 1 12); do
    is_enabled "$name" && return 0
    $REAL plugin enable "$name" >/dev/null 2>&1 && return 0
    echo "  plugin $name not ready yet, retry $n/12..." >&2
    sleep 5
  done
  return 1
}

if [ "$1" = "plugin" ] && [ "$2" = "install" ]; then
  shift 2
  args=("$@"); name=""; img=""; i=0
  while [ $i -lt ${#args[@]} ]; do
    a="${args[$i]}"
    if [ "$a" = "--alias" ]; then
      name="${args[$((i+1))]}"; i=$((i+2)); continue
    fi
    case "$a" in
      --alias=*) name="${a#--alias=}" ;;
      -*|*=*) ;;
      *) [ -z "$img" ] && img="$a" ;;
    esac
    i=$((i+1))
  done
  [ -z "$name" ] && name="$img"
  $REAL plugin install --disable "$@" || exit $?
  enable_retry "$name" && echo "$name" && exit 0
  exit 1
elif [ "$1" = "plugin" ] && [ "$2" = "enable" ]; then
  enable_retry "${@: -1}"
  exit $?
fi

exec $REAL "$@"
