#!/bin/bash

# default to no.
RUN_VACUUM=${RUN_VACUUM:-"no"}

if [[ "$RUN_VACUUM" != "yes" ]]; then
    exit 0
fi

# sleep for a random amount of time, so that we don't run this at the same time on all nodes.
sleep $(((RANDOM % 3600) + 1))

docker system prune --force
