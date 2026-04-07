#!/bin/bash

# Script to check AWS CloudWatch costs by region
# Usage: ./check_cloudwatch_costs.sh [--profile profile_name] [region]

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

echo "CloudWatch Cost Analysis - Region: $REGION (Last Month: $LAST_MONTH_START to $LAST_MONTH_END)"
echo "================================================================================="

# Debug: Check what services have costs in this period
echo "Debug: All services with costs in this period:"
aws ce get-cost-and-usage \
    --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE \
    $PROFILE \
    --query 'ResultsByTime[*].Groups[*].[Keys[0],Metrics.BlendedCost.Amount]' \
    --output text | \
    awk '$2>0 {print $1, $2}' | \
    grep -i cloudwatch

echo ""

# Get actual CloudWatch costs from Cost Explorer
echo "Checking CloudWatch costs..."
ACTUAL_COST=$(aws ce get-cost-and-usage \
    --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE \
    --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon CloudWatch"]}}' \
    $PROFILE \
    --query 'ResultsByTime[*].Groups[?Keys[0]==`Amazon CloudWatch`].Metrics.BlendedCost.Amount' \
    --output text | awk '{print $1}')

# Try alternative service names if first attempt is empty
if [ -z "$ACTUAL_COST" ] || [ "$ACTUAL_COST" = "None" ]; then
    ACTUAL_COST=$(aws ce get-cost-and-usage \
        --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END \
        --granularity MONTHLY \
        --metrics BlendedCost \
        --group-by Type=DIMENSION,Key=SERVICE \
        --filter '{"Dimensions":{"Key":"SERVICE","Values":["CloudWatch"]}}' \
        $PROFILE \
        --query 'ResultsByTime[*].Groups[?Keys[0]==`CloudWatch`].Metrics.BlendedCost.Amount' \
        --output text | awk '{print $1}')
fi

echo "Actual Total Cost from Cost Explorer: \$${ACTUAL_COST:-0.00}"
echo ""

# Quick counts (fast operations only)
echo "Quick Usage Summary:"
echo "-------------------"

# Count alarms (fast)
ALARMS=$(aws cloudwatch describe-alarms --region $REGION $PROFILE --max-items 100 --query 'length(MetricAlarms)' --output text 2>/dev/null | head -1)
echo "Alarms (first 100): ${ALARMS:-0}"

# Count dashboards (fast)
DASHBOARDS=$(aws cloudwatch list-dashboards --region $REGION $PROFILE --query 'length(DashboardEntries)' --output text 2>/dev/null)
echo "Dashboards: ${DASHBOARDS:-0}"

# Count log groups (fast)
LOG_GROUPS=$(aws logs describe-log-groups --region $REGION $PROFILE --limit 50 --query 'length(logGroups)' --output text 2>/dev/null)
echo "Log Groups (first 50): ${LOG_GROUPS:-0}"

echo ""
echo "Cost Breakdown by Usage Type:"
echo "-----------------------------"

# Get cost breakdown (this should be fast)
COST_BREAKDOWN=$(aws ce get-cost-and-usage \
    --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=USAGE_TYPE \
    --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon CloudWatch"]}}' \
    $PROFILE \
    --query 'ResultsByTime[*].Groups[*].[Keys[0],Metrics.BlendedCost.Amount]' \
    --output text 2>/dev/null)

if [ -n "$COST_BREAKDOWN" ]; then
    echo "$COST_BREAKDOWN" | awk 'NF==2 && $2>0 {printf "%-40s $%.4f\n", $1, $2}' | sort -k2 -nr
else
    echo "No cost breakdown data available"
fi

# Estimate costs based on usage
echo ""
echo "Estimated Costs Based on Usage:"
echo "-------------------------------"
ALARM_COST=$(echo "$ALARMS" | awk '{printf "%.2f", $1 * 0.10}')
DASHBOARD_COST=$(echo "$DASHBOARDS" | awk '{printf "%.2f", $1 * 3.00}')
echo "Alarms: \$$ALARM_COST (${ALARMS} × \$0.10)"
echo "Dashboards: \$$DASHBOARD_COST (${DASHBOARDS} × \$3.00)"
echo "Log Groups: Variable cost based on ingestion and storage"

echo ""
echo "Log Groups by Data Volume (Top 20):"
echo "===================================="

# Find longest log group name for formatting
MAX_LOG_LENGTH=$(aws logs describe-log-groups --region "$REGION" $PROFILE --query 'logGroups[*].logGroupName' --output text | tr '\t' '\n' | awk '{if(length > max) max = length} END {print max+5}')

if [ -z "$MAX_LOG_LENGTH" ] || [ "$MAX_LOG_LENGTH" -lt 30 ]; then
    MAX_LOG_LENGTH=50
fi

# Get log groups with size data and estimate costs (storage + ingestion)
printf "+%*s+------------+---------------+---------------+------------------+\n" "$MAX_LOG_LENGTH" "" | tr ' ' '-'
printf "| %-*s | Size (MB)  | Storage Cost  | Ingest Cost   | Est. Total Cost  |\n" "$MAX_LOG_LENGTH" "Log Group Name"
printf "+%*s+------------+---------------+---------------+------------------+\n" "$MAX_LOG_LENGTH" "" | tr ' ' '-'

# Get top 20 log groups by stored bytes
TOP_LOG_GROUPS=$(aws logs describe-log-groups --region "$REGION" $PROFILE \
    --query 'logGroups[*].[logGroupName,storedBytes]' \
    --output text | \
    sort -k2 -nr | \
    head -20)

while IFS=$'\t' read -r LOG_GROUP STORED_BYTES; do
    # Storage cost: $0.03/GB/month on storedBytes
    STORAGE_COST=$(echo "$STORED_BYTES" | awk '{printf "%.4f", $1/1024/1024/1024 * 0.03}')

    # Ingestion: sum daily IncomingBytes over last month via CloudWatch Metrics
    INCOMING_BYTES=$(aws cloudwatch get-metric-statistics \
        --region "$REGION" $PROFILE \
        --namespace "AWS/Logs" \
        --metric-name "IncomingBytes" \
        --dimensions "Name=LogGroupName,Value=${LOG_GROUP}" \
        --start-time "${LAST_MONTH_START}T00:00:00Z" \
        --end-time "${LAST_MONTH_END}T00:00:00Z" \
        --period 86400 \
        --statistics Sum \
        --query 'sum(Datapoints[*].Sum)' \
        --output text 2>/dev/null)

    if [ -z "$INCOMING_BYTES" ] || [ "$INCOMING_BYTES" = "None" ] || [ "$INCOMING_BYTES" = "null" ]; then
        INCOMING_BYTES=0
    fi

    # Ingestion cost: $0.50/GB ingested
    INGEST_COST=$(echo "$INCOMING_BYTES" | awk '{printf "%.4f", $1/1024/1024/1024 * 0.50}')

    # Total
    TOTAL_COST=$(echo "$STORAGE_COST $INGEST_COST" | awk '{printf "%.2f", $1 + $2}')
    SIZE_MB=$(echo "$STORED_BYTES" | awk '{printf "%.2f", $1/1024/1024}')

    printf "| %-*s | %10s | $%-13s | $%-13s | $%-15s |\n" \
        "$MAX_LOG_LENGTH" "$LOG_GROUP" "$SIZE_MB" "$STORAGE_COST" "$INGEST_COST" "$TOTAL_COST"
done <<< "$TOP_LOG_GROUPS"

# Close table
printf "+%*s+------------+---------------+---------------+------------------+\n" "$MAX_LOG_LENGTH" "" | tr ' ' '-'