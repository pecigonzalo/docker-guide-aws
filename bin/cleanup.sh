#!/bin/bash
# this script cleans up and nodes that have been upgraded and no longer need to be in the swarm.
if [ "$NODE_TYPE" == "worker" ]; then
    # this doesn't run on workers, only managers.
    exit 0
fi

# script runs via cron every 5 minutes, so all of them will start at the same time. Add a random
# delay so they don't step on each other when pulling items from the queue.
sleep $(((RANDOM % 10) + 1))

# make sure we are not in process of shutting down.
if [ -e /tmp/.shutdown-init ]; then
    echo "We are shutting down, no need to continue."
    # shutdown has initialized, don't start because we might not be able to finish.
    exit 0
fi

# find any nodes that are marked as down, and remove from the swarm
MESSAGES=$(aws sqs receive-message --region "$REGION" --queue-url "$CLEANUP_QUEUE" --max-number-of-messages 10 --wait-time-seconds 10 --visibility-timeout 5)

COUNT=$(echo "$MESSAGES" | jq -r '.Messages | length')

# default to 0, if empty
COUNT="${COUNT:-0}"

for ((i = 0; i < COUNT; i++)); do
    BODY=$(echo "$MESSAGES" | jq -r '.Messages['${i}'].Body')
    RECEIPT=$(echo "$MESSAGES" | jq --raw-output '.Messages['${i}'] .ReceiptHandle')
    echo "Remove NodeID=$BODY"
    docker node rm --force "$BODY"
    RESULT=$?
    if [ $RESULT -eq 0 ]; then
        echo "We were able to remove node from swarm, delete message from queue"
        aws sqs delete-message --region "$REGION" --queue-url "$CLEANUP_QUEUE" --receipt-handle "$RECEIPT"
        echo "message deleted"
    else
        echo "We were not able to remove node from swarm, don't delete. RESULT=$RESULT"
    fi
done
