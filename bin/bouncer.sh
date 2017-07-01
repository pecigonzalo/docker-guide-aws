#!/bin/bash
# this script cleans up any manager nodes that might have left the swarm without
# telling the swarm about it.

if [ "$NODE_TYPE" == "worker" ]; then
    # this doesn't run on workers, only managers.
    exit 0
fi

IS_LEADER=$(docker node inspect self -f '{{ .ManagerStatus.Leader }}')
if [[ "$IS_LEADER" != "true" ]]; then
    # not the leader, no need to continue.
    exit 0
fi

DOWN_LIST=$(docker node inspect $(docker node ls --filter role=manager -q) | jq -r '.[] | select(.ManagerStatus.Reachability != "reachable") | .ManagerStatus.Addr | split(":")[0]')

if [ -z "$DOWN_LIST" ]; then
    # there are no nodes down, exit now.
    exit 0
fi

echo "Found some nodes that are unreachable. DOWN_LIST=$DOWN_LIST"

echo "== Current node list =="
docker node ls

# make API calls to get status of down nodes
for I in $DOWN_LIST; do

    # API call to get the instance data for the given IP
    STATUS=$(aws ec2 describe-instances --region=$REGION --filters "Name=tag:swarm-stack-id,Values=$STACK_ID" "Name=private-ip-address,Values=$I" | jq -r ".Reservations[] | .Instances[] | .State.Name")
    # STATUS could be one of the following pending | running | shutting-down | terminated | stopping | stopped
    # if terminated the API might Return nothing (some terminated instances might stay around for up to an hour).
    # what if AZ is experiencing a service disruption, it will remove that node, is that OK?

    if [[ "$STATUS" == "" ]] || [[ "$STATUS" == "terminated" ]]; then
        # we currently only remove if instance is now gone, or terminated
        # those are the only two we know won't be coming back.
        echo "$I has a status of '"$STATUS"', remove it"
        echo "get Node_ID for $I"
        NODE_ID=$(docker node inspect $(docker node ls --filter role=manager -q) | jq --arg I $I -r '.[] | select(.ManagerStatus.Addr | split(":")[0] == $I) | .ID')
        echo "$I is NODE_ID=$NODE_ID, demote and remove from swarm"
        docker node demote $NODE_ID
        docker node rm $NODE_ID
        echo "$NODE_ID [$I] Should be removed now"
    else
        echo "$I has status of '"$STATUS"', don't remove"
    fi
done

echo "Final node list"
docker node ls
echo "== Finished =="
