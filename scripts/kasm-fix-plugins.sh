#!/bin/bash
# kasm-fix-plugins.sh
#
# Runs at boot (from kasm-plugins.service) after Docker and before Kasm.
# After a reboot, Docker restores plugins with the same short start timer,
# so on a slow VM the Kasm logging plugin can come back disabled and every
# Kasm container then fails to start. This re-enables the plugins, using the
# retry wrapper in /usr/local/bin/docker.

sleep 15
for p in $(/usr/bin/docker plugin ls --format '{{.Name}}' | grep -E 'kasm|rclone'); do
  /usr/local/bin/docker plugin enable "$p" || true
done
exit 0
