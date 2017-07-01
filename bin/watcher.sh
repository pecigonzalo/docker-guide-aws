#!/bin/bash
# This script will prevent autoscaling from terminating until we leave the swarm
MYIP=$(wget -qO- http://169.254.169.254/latest/meta-data/local-ipv4)
MYNODE=$(wget -qO- http://169.254.169.254/latest/meta-data/instance-id)

QUEUE=$SWARM_QUEUE
VPC_ID=$VPC_ID # TODO pass in.
# also pass in DYNAMODB_TABLE

if [ -e /tmp/.shutdown-init ]; then
    echo "We are already shutting down, no need to continue."
    # shutdown has already initialized.
    exit 0
fi

# echo "Find our NODE:"
if [ "$NODE_TYPE" == "manager" ]; then
    # manager
    NODE_ID=$(docker node inspect self | jq -r '.[].ID')
else
    # worker
    NODE_ID=$(docker info | grep NodeID | cut -f2 -d: | sed -e 's/^[ \t]*//')
fi
echo "NODE: $NODE_ID"
echo "NODE_TYPE=$NODE_TYPE"

# script runs via cron every minute, so all of them will start at the same time. Add a random
# delay so they don't step on each other when pulling items from the queue.
# echo "Sleep for a short time (1-10 seconds). To prevent scripts from stepping on each other"
sleep $(((RANDOM % 10) + 1))
# echo "Finished sleep, lets get going."

# Find SQS message with termination message
FOUND=false
MESSAGES=$(aws sqs receive-message --region "$REGION" --queue-url "$QUEUE" --max-number-of-messages 10 --wait-time-seconds 10 --visibility-timeout 1)
# echo "$MESSAGES"
COUNT=$(echo "$MESSAGES" | jq -r '.Messages | length')
# echo "$COUNT messages"

# default to 0, if empty
COUNT="${COUNT:-0}"

for ((i = 0; i < COUNT; i++)); do
    BODY=$(echo "$MESSAGES" | jq -r '.Messages['${i}'].Body')
    RECEIPT=$(echo "$MESSAGES" | jq --raw-output '.Messages['${i}'] .ReceiptHandle')
    LIFECYCLE=$(echo "$BODY" | jq --raw-output '.LifecycleTransition')
    INSTANCE=$(echo "$BODY" | jq --raw-output '.EC2InstanceId')
    if [[ $LIFECYCLE == 'autoscaling:EC2_INSTANCE_TERMINATING' ]] && [[ $INSTANCE == "$MYNODE" ]]; then
        echo "Found a shutdown event for $MYNODE"
        TOKEN=$(echo "$BODY" | jq --raw-output '.LifecycleActionToken')
        HOOK=$(echo "$BODY" | jq --raw-output '.LifecycleHookName')
        ASG=$(echo "$BODY" | jq --raw-output '.AutoScalingGroupName')
        FOUND=true
        echo "Delete the record from SQS"
        aws sqs delete-message --region "$REGION" --queue-url "$QUEUE" --receipt-handle "$RECEIPT"
        echo "Finished deleting the sqs record."
        break
    elif [[ $LIFECYCLE != 'autoscaling:EC2_INSTANCE_TERMINATING' ]]; then
        # There is a testing message on the queue at start we don't need, remove it, so it doesn't clog queue in future.
        echo "Message isn't one we care about, remove it."
        aws sqs delete-message --region "$REGION" --queue-url "$QUEUE" --receipt-handle "$RECEIPT"
    fi
done
# If not not found, exit
if [[ $FOUND == false ]]; then
    exit 0
fi

echo "Found something, clean up and then shut down."

# create the .shutdown-init file so that we can let future cron tasks
# know that we have already started shutdown.
touch /tmp/.shutdown-init
date

if [ "$NODE_TYPE" == "manager" ]; then
    # we are a manager, handle manager shutdown.

    MANAGER=$(aws dynamodb get-item --region "$REGION" --table-name "$DYNAMODB_TABLE" --key '{"node_type":{"S": "primary_manager"}}')
    CURRENT_MANAGER_IP=$(echo "$MANAGER" | jq -r '.Item.ip.S')
    export CURRENT_MANAGER_IP

    echo "Current manager IP = $CURRENT_MANAGER_IP ; my IP = $MYIP"

    if [ "$CURRENT_MANAGER_IP" == "$MYIP" ]; then
        # this node is currently the primary in dynamodb, update to a new manager since this one is going away.
        echo "The current manager in dynamodb is this one, we need to replace with another manager."

        ########
        # find the current list of managers using AWS API
        # Using the API is a little more risky because it could find a new manager node that is starting up, but isn't
        # ready to accept join requests.
        #
        # HOSTNAMES=$(aws ec2 describe-vpc-attribute --vpc-id="$VPC_ID" --region=$REGION --attribute=enableDnsHostnames --output=text | grep ENABLEDNSHOSTNAMES | awk '{print $2}')
        # if [[ "$HOSTNAMES" == "True" ]]; then
        #     MANAGERS=$(aws ec2 describe-instances --filter Name=instance-state-name,Values=running --filter Name=tag-key,Values=swarm-stack-id Name=tag-value,Values=$STACK_ID --filter Name=tag-key,Values=swarm-node-type Name=tag-value,Values=manager --output=text --region=$REGION | grep PRIVATEIPADDRESSES | awk '{print $4}')
        # else
        #     MANAGERS=$(aws ec2 describe-instances --filter Name=instance-state-name,Values=running --filter Name=tag-key,Values=swarm-stack-id Name=tag-value,Values=$STACK_ID --filter Name=tag-key,Values=swarm-node-type Name=tag-value,Values=manager --output=text --region=$REGION | grep PRIVATEIPADDRESSES | awk '{print $3}')
        # fi

        #########
        # find the current Leader using docker node list
        # this is a little less risky then the AMZ API query since we know these are already in the swarm
        # and they are reachable. We try and set the dynamodb primary ip to the current leader
        # if we are the leader, then we will look at the other managers in the list, and fine one, that isn't us
        IS_LEADER=$(docker node inspect self -f '{{ .ManagerStatus.Leader }}')
        # if we are the leader, we don't want to use that one.
        if [[ "$IS_LEADER" == "true" ]]; then
            # we are the current leader, sleep for 3 minutes, incase this is a scale down event
            # this will allow the other none leaders to demote themselves first. removing themselves
            # from the quorum. If we don't there is a race condition, and all of them will try to
            # demote at the same time, and cause problems. Leaving us with no leader, but still a record
            # in dynamodb. the delay will help prevent this.
            sleep 180
            # find the current reachable manager list, using docker node list
            MANAGERS=$(docker node inspect $(docker node ls --filter role=manager -q) | jq -r '.[] | select(.ManagerStatus.Reachability == "reachable") | .ManagerStatus.Addr | split(":")[0]')
            NEW_MANAGER_IP=""
            # Find first node that's not myself
            echo "List of available Managers = $MANAGERS"
            for I in $MANAGERS; do
                echo "Checking $I"
                if [[ $I == "$MYIP" ]]; then
                    echo "$I == $MYIP, skip this one."
                    continue
                fi
                echo "Found a good one, set NEW_MANAGER_IP= $I"
                NEW_MANAGER_IP=$I
                break
            done
        else
            CURRENT_LEADER_IP=$(docker node inspect $(docker node ls --filter role=manager -q) | jq -r '.[] | select(.ManagerStatus.Leader == true) | .ManagerStatus.Addr | split(":")[0]')
            echo "We are not the leader, let's use the Leader = $CURRENT_LEADER_IP"
            # we are not the leader, lets use the leader as the new primary IP in dynamodb.
            NEW_MANAGER_IP=$CURRENT_LEADER_IP
        fi

        if [[ "$NEW_MANAGER_IP" == "" ]]; then
            echo "There is no new manager available. Most likely a scale down event, and this was the last manager"
            echo "delete record in dynamodb table"
            # this will allow us to start from scratch on scale up event from scratch.
            aws dynamodb delete-item --table-name "$DYNAMODB_TABLE" --region "$REGION" --key '{"node_type":{"S": "primary_manager"}}'
            LAST_MANAGER=1
        else
            echo "update the dynamodb table with IP = $NEW_MANAGER_IP"
            # update the primary manager IP item in dynamodb
            aws dynamodb put-item \
                --table-name "$DYNAMODB_TABLE" \
                --region "$REGION" \
                --item '{"node_type":{"S": "primary_manager"},"ip": {"S":"'"$NEW_MANAGER_IP"'"}}' \
                --return-consumed-capacity TOTAL
        fi
    fi

    # if not the last manager, demote, if it is the last manager, then we can't demote, it won't let us.
    if [ -z "$LAST_MANAGER" ]; then
        echo "demote the node from manager to worker for NODE: $NODE_ID"
        docker node demote "$NODE_ID"
    else
        echo "This is the last manager in the swarm."
    fi
    echo "Give time for the demotion to take place"
    sleep 30

fi

# remove the node from swarm for both the manager and the worker.
echo "Remove the node"
# we can't remove ourselves, only a manager still in the swarm can remove us.
# send a message to one of them to cleanup after us.
#docker node rm $NODE_ID
echo "Send NODE_ID=$NODE_ID to CLEANUP_QUEUE=$CLEANUP_QUEUE"
aws sqs send-message --region "$REGION" --queue-url "$CLEANUP_QUEUE" --message-body "$NODE_ID" --delay-seconds 10

echo "Lets AWS know we can shut down now."
# let autoscaler know it can continue.
aws autoscaling complete-lifecycle-action --region "$REGION" --lifecycle-action-token "$TOKEN" --lifecycle-hook-name "$HOOK" --auto-scaling-group-name "$ASG" --lifecycle-action-result CONTINUE
echo "Complete"
date
