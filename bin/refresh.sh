#!/bin/bash
# this script refreshes the swarm primary manager in dynamodb if it has changed.
if [ "$NODE_TYPE" == "worker" ]; then
    # this doesn't run on workers, only managers.
    exit 0
fi

# script runs via cron every 5 minutes, so all of them will start at the same time.
# Add a random delay so they don't step on each
sleep $(((RANDOM % 10) + 1))

IS_LEADER=$(docker node inspect self -f '{{ .ManagerStatus.Leader }}')

if [[ "$IS_LEADER" == "true" ]]; then
    # we are the leader, We only need to call once, so we only call from the current leader.
    MANAGER=$(aws dynamodb get-item --region "$REGION" --table-name "$DYNAMODB_TABLE" --key '{"node_type":{"S": "primary_manager"}}')
    MANAGER_IP=$(echo "$MANAGER" | jq -r '.Item.ip.S')
    MY_IP=$(wget -qO- http://169.254.169.254/latest/meta-data/local-ipv4)

    if [[ "$MANAGER_IP" != "$MY_IP" ]]; then
        echo "Primary Manager has changed, updating dynamodb with new IP From $MANAGER_IP to $MY_IP"
        aws dynamodb put-item \
            --table-name "$DYNAMODB_TABLE" \
            --region "$REGION" \
            --item '{"node_type":{"S": "primary_manager"},"ip": {"S":"'"$MY_IP"'"}}' \
            --return-consumed-capacity TOTAL
    fi

fi
