#!/bin/bash
# this script calls buoy with correct parameters
if [ "$NODE_TYPE" == "worker" ]; then
    # this doesn't run on workers, only managers.
    exit 0
fi

IS_LEADER=$(docker node inspect self -f '{{ .ManagerStatus.Leader }}')

if [[ "$IS_LEADER" == "true" ]]; then
    # we are the leader, so call buoy. We only need to call once, so we only call from the current leader.
    NUM_MANAGERS=$(docker info | grep Managers | cut -f2 -d: | sed -e 's/^[ \t]*//')
    TOTAL_NODES=$(docker info | grep Nodes | cut -f2 -d: | sed -e 's/^[ \t]*//')
    NUM_WORKERS=$((TOTAL_NODES - NUM_MANAGERS))
    NUM_SERVICES=$(docker service ls -q | wc -w)
    DOCKER_VERSION=$(docker version --format '{{.Server.Version}}')
    SWARM_ID=$(docker info | grep ClusterID | cut -f2 -d: | sed -e 's/^[ \t]*//')
    CHANNEL=${CHANNEL:-beta}
    if [[ $DOCKER_VERSION =~ ^[0-9]+.[0-9]+.[0-9]+$ ]]; then
        CHANNEL="stable"
    fi

    /usr/bin/buoy -event="swarm:ping" -workers=$NUM_WORKERS -managers="$NUM_MANAGERS" -services="$NUM_SERVICES" \
        -docker_version="$DOCKER_VERSION" -swarm_id="$SWARM_ID" -channel=$CHANNEL
fi
