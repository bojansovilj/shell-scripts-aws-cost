#!/bin/bash

# Script to check SQS message metrics
# Usage: ./check_sqs_metrics.sh [--profile profile_name] [region]

PROFILE=""
REGION=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)
            PROFILE="--profile $2"
            shift 2
            ;;
        *)
            REGION="$1"
            shift
            ;;
    esac
done

# Set default region if not provided
if [ -z "$REGION" ]; then
    REGION=$(aws configure get region $PROFILE)
fi

# Calculate last month dates
LAST_MONTH_START=$(date -v-1m -v1d '+%Y-%m-%dT00:00:00Z')
LAST_MONTH_END=$(date -v1d '+%Y-%m-%dT00:00:00Z')
PERIOD=2592000

echo "Fetching SQS queues in region: $REGION (Last Month: $LAST_MONTH_START to $LAST_MONTH_END)..."
QUEUES=$(aws sqs list-queues --region $REGION $PROFILE --query 'QueueUrls[]' --output text)

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
        --start-time $LAST_MONTH_START \
        --end-time $LAST_MONTH_END \
        --period $PERIOD \
        --statistics Sum \
        --region $REGION \
        $PROFILE \
        --query 'Datapoints[0].Sum' \
        --output text)
    
    if [ "$RESULT" = "None" ] || [ -z "$RESULT" ]; then
        echo "$QUEUE_NAME: 0"
    else
        echo "$QUEUE_NAME: $RESULT"
    fi
done
