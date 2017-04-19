#!/usr/bin/env bash

set -e          # exit on command errors
set -o nounset  # abort on unbound variable
set -o pipefail # capture fail exit codes in piped commands

echo "Initialize logging for guide daemons"
printenv | cat - /usr/docker/crontab.txt >temp && mv temp /etc/crontab

#/usr/bin/crontab /usr/docker/crontab.txt

# setup symlink to output logs from relevant scripts to container logs
# Create the log file to be able to run tail
set +e
ln -s /proc/1/fd/1 /var/log/cron/refresh.log
ln -s /proc/1/fd/1 /var/log/cron/watcher.log
ln -s /proc/1/fd/1 /var/log/cron/cleanup.log
ln -s /proc/1/fd/1 /var/log/cron/vacuum.log
ln -s /proc/1/fd/1 /var/log/cron/cron.log
set -e
# start cron
# /usr/sbin/crond -f -l 9 -L /var/log/cron.log
cron -f
