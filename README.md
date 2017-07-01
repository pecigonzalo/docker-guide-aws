# Docker Swarm for AWS Guide

This container *guides* the cluster instances through its lifecycle performing maintenance tasks

*Example project:* **[Terraform docker-swarm](https://github.com/pecigonzalo/tf-docker-swarm)**

### Description
This container performs several maintenance and cleanup operations for a Docker Swarm node running on AWS.

##### Tasks
- **Cleanup (Manager Nodes) every 5 minutes**
Removes downed/downscaled nodes from the swarm based on events on a SQS queue.

- **Refresh (Manager Nodes) every 4 minutes**
Updates the DynamodDB table with the current Docker Swarm primary Manager.

- **Vacuum (All Nodes) every day between 00 and 01**
Runs `docker system prune --force` to remove all dangling resources.

- **Watcher (All Nodes) every minute**
Handles AutoScalingGroup Instance shutdown by reading events for the node on a SQS queue and notifying the ASG once we are done exiting the swarm.

### Usage
##### Paramaters
| Parameter | Example | Description |
|-----------|:-------:|:------------|
| DYNAMODB_TABLE | - | DynamodDB table ID |
| NODE_TYPE | worker / manager | Role of the node we are running on |
| REGION | eu-central-1 | AWS Region ID|
| VPC_ID | vpc-123123 | AWS VPC ID |
| SWARM_QUEUE | - | SQS Queue ID for swarm control |
| CLEANUP_QUEUE | - | SQS Queue ID for cleaup actions |
| RUN_VACUUM | yes / no | Enable or Disable Vacuum actions |

##### Example
```
docker run -d \
  --name=guide-aws \
  --restart=always \
  -e DYNAMODB_TABLE=$DYNAMODB_TABLE \
  -e NODE_TYPE=$NODE_TYPE \
  -e REGION=$AWS_REGION \
  -e VPC_ID=$VPC_ID \
  -e SWARM_QUEUE="$SWARM_QUEUE" \
  -e CLEANUP_QUEUE="$CLEANUP_QUEUE" \
  -e RUN_VACUUM=$RUN_VACUUM \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /usr/bin/docker:/usr/bin/docker \
  pecigonzalo/docker-guide-aws
```
