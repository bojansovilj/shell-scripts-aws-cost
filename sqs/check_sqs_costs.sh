#!/bin/bash

# Script to check SQS costs and metrics by region
# Usage: ./check_sqs_costs.sh [--profile profile_name] [region]

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
LAST_MONTH_START=$(date -v-1m -v1d '+%Y-%m-%d')
LAST_MONTH_END=$(date -v1d '+%Y-%m-%d')
LAST_MONTH_START_ISO=$(date -v-1m -v1d '+%Y-%m-%dT00:00:00Z')
LAST_MONTH_END_ISO=$(date -v1d '+%Y-%m-%dT00:00:00Z')
PERIOD=2592000

echo "SQS Queue Analysis - Region: $REGION (Last Month: $LAST_MONTH_START to $LAST_MONTH_END)"
echo "================================================================================"

# Get actual SQS costs from Cost Explorer
ACTUAL_COST=$(aws ce get-cost-and-usage \
    --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE \
    --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Simple Queue Service"]}}' \
    $PROFILE \
    --query 'ResultsByTime[*].Groups[?Keys[0]==`Amazon Simple Queue Service`].Metrics.BlendedCost.Amount' \
    --output text | awk '{print $1}')

echo "Actual Total Cost from Cost Explorer: \$${ACTUAL_COST:-0.00}"
echo ""

# Get SQS queues
QUEUES=$(aws sqs list-queues --region $REGION $PROFILE --query 'QueueUrls[]' --output text)

if [ -z "$QUEUES" ]; then
    echo "No queues found in region $REGION"
    exit 0
fi

echo "SQS Queues Analysis:"
echo "==================="

# Find longest queue name for formatting (limit to avoid xargs issues)
MAX_LENGTH=$(aws sqs list-queues --region $REGION $PROFILE --query 'QueueUrls[]' --output text | \
    head -20 | tr ' ' '\n' | while read url; do basename "$url"; done | \
    awk '{if(length > max) max = length} END {print max+5}')

if [ -z "$MAX_LENGTH" ] || [ "$MAX_LENGTH" -lt 30 ]; then
    MAX_LENGTH=50
elif [ "$MAX_LENGTH" -gt 80 ]; then
    MAX_LENGTH=80
fi

# Create table header
printf "+%*s+----------+-------+---------------+----------------+-------------+\n" $MAX_LENGTH | tr ' ' '-'
printf "| %-*s | Messages | Depth | Avg Depth     | Est. Requests  | Est. Price  |\n" $MAX_LENGTH "Queue Name"
printf "+%*s+----------+-------+---------------+----------------+-------------+\n" $MAX_LENGTH | tr ' ' '-'

# Initialize totals
total_messages=0
total_requests=0
total_cost=0

for QUEUE_URL in $QUEUES; do
    QUEUE_NAME=$(basename $QUEUE_URL)
    
    # Truncate very long queue names for display
    DISPLAY_NAME="$QUEUE_NAME"
    if [ ${#QUEUE_NAME} -gt 75 ]; then
        DISPLAY_NAME="${QUEUE_NAME:0:72}..."
    fi
    
    # Get messages sent (last month)
    messages_sent=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/SQS \
        --metric-name NumberOfMessagesSent \
        --dimensions Name=QueueName,Value=$QUEUE_NAME \
        --start-time $LAST_MONTH_START_ISO \
        --end-time $LAST_MONTH_END_ISO \
        --period $PERIOD \
        --statistics Sum \
        --region $REGION \
        $PROFILE \
        --query 'Datapoints[0].Sum' \
        --output text 2>/dev/null)
    
    # Get current queue depth
    queue_depth=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/SQS \
        --metric-name ApproximateNumberOfVisibleMessages \
        --dimensions Name=QueueName,Value=$QUEUE_NAME \
        --start-time $(date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v-1H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u --date='1 hour ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null) \
        --end-time $(date -u '+%Y-%m-%dT%H:%M:%SZ') \
        --period 3600 \
        --statistics Average \
        --region $REGION \
        $PROFILE \
        --query 'Datapoints[0].Average' \
        --output text 2>/dev/null)
    
    # Get average queue depth (last month)
    avg_depth=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/SQS \
        --metric-name ApproximateNumberOfVisibleMessages \
        --dimensions Name=QueueName,Value=$QUEUE_NAME \
        --start-time $LAST_MONTH_START_ISO \
        --end-time $LAST_MONTH_END_ISO \
        --period $PERIOD \
        --statistics Average \
        --region $REGION \
        $PROFILE \
        --query 'Datapoints[0].Average' \
        --output text 2>/dev/null)
    
    # Handle None/empty values
    if [ "$messages_sent" = "None" ] || [ -z "$messages_sent" ]; then
        messages_sent=0
    fi
    if [ "$queue_depth" = "None" ] || [ -z "$queue_depth" ]; then
        queue_depth=0
    fi
    if [ "$avg_depth" = "None" ] || [ -z "$avg_depth" ]; then
        avg_depth=0
    fi
    
    # Estimate total requests (sent + received + deleted)
    # Assume: 1 send + 1 receive + 1 delete per message = 3 requests per message
    # Plus some polling requests (estimate 20% overhead)
    est_requests=$(echo "$messages_sent" | awk '{printf "%.0f", $1 * 3.2}')
    
    # Calculate cost: $0.40 per million requests (first 1M free per month)
    if [ "$est_requests" -gt 1000000 ]; then
        billable_requests=$(echo "$est_requests" | awk '{print $1 - 1000000}')
        est_cost=$(echo "$billable_requests" | awk '{printf "%.4f", ($1 / 1000000) * 0.40}')
    else
        est_cost="0.0000"
    fi
    
    # Format numbers for display
    messages_display=$(echo "$messages_sent" | awk '{
        if($1>=1000000000) printf "%.1fB", $1/1000000000;
        else if($1>=1000000) printf "%.1fM", $1/1000000;
        else if($1>=1000) printf "%.1fK", $1/1000;
        else printf "%.0f", $1
    }')
    depth_display=$(echo "$queue_depth" | awk '{printf "%.0f", $1}')
    avg_depth_display=$(echo "$avg_depth" | awk '{printf "%.1f", $1}')
    requests_display=$(echo "$est_requests" | awk '{
        if($1>=1000000000) printf "%.1fB", $1/1000000000;
        else if($1>=1000000) printf "%.1fM", $1/1000000;
        else if($1>=1000) printf "%.1fK", $1/1000;
        else printf "%.0f", $1
    }')
    
    printf "| %-*s | %-8s | %-5s | %-13s | %-14s | \$%-10s |\n" $MAX_LENGTH "$DISPLAY_NAME" "$messages_display" "$depth_display" "$avg_depth_display" "$requests_display" "$est_cost"
    
    # Add to totals
    total_messages=$(echo "$total_messages $messages_sent" | awk '{print $1 + $2}')
    total_requests=$(echo "$total_requests $est_requests" | awk '{print $1 + $2}')
    total_cost=$(echo "$total_cost $est_cost" | awk '{print $1 + $2}')
done

# Close table
printf "+%*s+----------+-------+---------------+----------------+-------------+\n" $MAX_LENGTH | tr ' ' '-'

echo ""
echo "Cost Estimation Summary:"
echo "======================="
total_requests_display=$(echo "$total_requests" | awk '{
    if($1>=1000000000) printf "%.1fB", $1/1000000000;
    else if($1>=1000000) printf "%.1fM", $1/1000000;
    else if($1>=1000) printf "%.1fK", $1/1000;
    else printf "%.0f", $1
}')
echo "Total estimated requests: $total_requests_display"
echo "Estimated monthly cost: \$$(echo "$total_cost" | awk '{printf "%.2f", $1}')"
echo "First 1M requests per month are free"
echo ""
echo "SQS Pricing (us-east-1):"
echo "========================"
echo "Standard Queue:"
echo "  First 1M requests/month: Free"
echo "  Beyond 1M: \$0.40 per million requests"
echo ""
echo "FIFO Queue:"
echo "  First 1M requests/month: Free"
echo "  Beyond 1M: \$0.50 per million requests"
echo ""
echo "Cost Optimization Tips:"
echo "======================"
echo "1. Use batch operations to reduce request count"
echo "2. Implement efficient polling strategies"
echo "3. Use long polling to reduce empty receives"
echo "4. Monitor queue depth to optimize consumers"
echo "5. Consider message lifecycle policies"
