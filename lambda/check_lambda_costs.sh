#!/bin/bash

# Script to check AWS Lambda costs by region
# Usage: ./check_lambda_costs.sh [--profile profile_name] [region]

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

# Get actual Lambda costs from Cost Explorer
ACTUAL_COST=$(aws ce get-cost-and-usage \
    --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE \
    --filter '{"Dimensions":{"Key":"SERVICE","Values":["AWS Lambda"]}}' \
    $PROFILE \
    --query 'ResultsByTime[*].Groups[?Keys[0]==`AWS Lambda`].Metrics.BlendedCost.Amount' \
    --output text | awk '{print $1}')

echo "Lambda Function Analysis - Region: $REGION (Last Month: $LAST_MONTH_START to $LAST_MONTH_END)"
echo "Actual Total Cost from Cost Explorer: \$$ACTUAL_COST"
echo ""

# Find longest function name to set column width
MAX_LENGTH=$(aws lambda list-functions --region $REGION $PROFILE --query 'Functions[*].FunctionName' --output text | tr '\t' '\n' | awk '{if(length > max) max = length} END {print max+5}')

# Create table header
printf "+%*s+----------+-------+---------------+----------------+-------------+\n" $MAX_LENGTH | tr ' ' '-'
printf "| %-*s | Memory   | Runs  | Avg Duration  | Total Duration | Est. Price  |\n" $MAX_LENGTH "Function Name"
printf "+%*s+----------+-------+---------------+----------------+-------------+\n" $MAX_LENGTH | tr ' ' '-'

# Get function details with estimated cost calculation
for func in $(aws lambda list-functions --region $REGION $PROFILE --query 'Functions[*].FunctionName' --output text); do
    # Get function memory size
    memory=$(aws lambda get-function --function-name "$func" --region $REGION $PROFILE --query 'Configuration.MemorySize' --output text 2>/dev/null)
    
    # Get CloudWatch metrics for invocations and duration
    invocations=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/Lambda \
        --metric-name Invocations \
        --dimensions Name=FunctionName,Value="$func" \
        --start-time "${LAST_MONTH_START}T00:00:00Z" \
        --end-time "${LAST_MONTH_END}T00:00:00Z" \
        --period 2592000 \
        --statistics Sum \
        --region $REGION \
        $PROFILE \
        --query 'Datapoints[0].Sum' \
        --output text 2>/dev/null)
    
    duration=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/Lambda \
        --metric-name Duration \
        --dimensions Name=FunctionName,Value="$func" \
        --start-time "${LAST_MONTH_START}T00:00:00Z" \
        --end-time "${LAST_MONTH_END}T00:00:00Z" \
        --period 2592000 \
        --statistics Average,Sum \
        --region $REGION \
        $PROFILE \
        --query 'Datapoints[0].[Average,Sum]' \
        --output text 2>/dev/null)
    
    if [ -n "$invocations" ] && [ "$invocations" != "None" ] && [ "$invocations" != "" ]; then
        invocations=$(echo $invocations | xargs)
        avg_duration=$(echo $duration | awk '{print $1}' | awk '{printf "%.0f", $1}')
        total_duration=$(echo $duration | awk '{print $2}' | awk '{printf "%.0f", $1}')
        
        # Estimate cost: GB-seconds * $0.0000166667 + invocations * $0.0000002
        gb_seconds=$(echo "$memory $total_duration" | awk '{printf "%.2f", ($1/1024) * ($2/1000)}')
        est_price=$(echo "$gb_seconds $invocations" | awk '{printf "%.4f", $1 * 0.0000166667 + $2 * 0.0000002}')
        
        printf "| %-*s | %-8s | %-5s | %-13s | %-14s | \$%-10s |\n" $MAX_LENGTH "$func" "${memory}MB" "$invocations" "${avg_duration}ms" "${total_duration}ms" "$est_price"
    else
        printf "| %-*s | %-8s | %-5s | %-13s | %-14s | \$%-10s |\n" $MAX_LENGTH "$func" "${memory}MB" "0" "No runs" "0ms" "0.0000"
    fi
done

# Close table
printf "+%*s+----------+-------+---------------+----------------+-------------+\n" $MAX_LENGTH | tr ' ' '-'