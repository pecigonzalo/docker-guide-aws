#!/usr/bin/env bash

set -e          # exit on command errors
set -o nounset  # abort on unbound variable
set -o pipefail # capture fail exit codes in piped commands

# set system wide env variables, so they are available to ssh connections
/usr/bin/env >/etc/environment

echo "Initialize logging for guide daemons"
# setup symlink to output logs from relevant scripts to container logs
ln -s /proc/1/fd/1 /var/log/docker/refresh.log
ln -s /proc/1/fd/1 /var/log/docker/watcher.log
ln -s /proc/1/fd/1 /var/log/docker/cleanup.log

# start cron
/usr/sbin/crond -f -l 9 -L /var/log/cron.log
