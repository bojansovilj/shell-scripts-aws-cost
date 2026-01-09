#!/bin/bash

PROFILE="aws_cli_profile"
START_TIME="2025-12-10T00:00:00Z"
END_TIME="2026-01-09T00:00:00Z"
PERIOD=2592000

echo "Fetching SQS queues..."
QUEUES=$(aws sqs list-queues --profile $PROFILE --query 'QueueUrls[]' --output text)

if [ -z "$QUEUES" ]; then
    echo "No queues found"
    exit 0
fi

echo "Checking metrics for all queues..."
echo "=================================="

for QUEUE_URL in $QUEUES; do
    QUEUE_NAME=$(basename $QUEUE_URL)
    
    RESULT=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/SQS \
        --metric-name NumberOfMessagesSent \
        --dimensions Name=QueueName,Value=$QUEUE_NAME \
        --start-time $START_TIME \
        --end-time $END_TIME \
        --period $PERIOD \
        --statistics Sum \
        --profile $PROFILE \
        --query 'Datapoints[0].Sum' \
        --output text)
    
    if [ "$RESULT" = "None" ] || [ -z "$RESULT" ]; then
        echo "$QUEUE_NAME: 0"
    else
        echo "$QUEUE_NAME: $RESULT"
    fi
done
