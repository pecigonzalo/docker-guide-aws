docker run \
  --log-driver=json-file \
  --name=guide-aws \
  --restart=always \
  -d \
  -e DYNAMODB_TABLE=$DYNAMODB_TABLE \
  -e NODE_TYPE=$NODE_TYPE \
  -e REGION=$AWS_REGION \
  -e INSTANCE_NAME=$INSTANCE_NAME \
  -e VPC_ID=$VPC_ID \
  -e ACCOUNT_ID=$ACCOUNT_ID \
  -e SWARM_QUEUE="$SWARM_QUEUE" \
  -e CLEANUP_QUEUE="$CLEANUP_QUEUE" \
  -e RUN_VACUUM=$RUN_VACUUM \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /usr/bin/docker:/usr/bin/docker \
  pecigonzalo/docker-guide-aws
