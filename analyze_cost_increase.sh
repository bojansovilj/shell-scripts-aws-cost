#!/bin/bash

# Script to analyze AWS cost increases
# Usage: ./analyze_cost_increase.sh [--profile profile_name]

PROFILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)
            PROFILE="--profile $2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

echo "AWS Cost Increase Analysis"
echo "=========================="
echo ""

# Calculate date ranges
CURRENT_MONTH_START=$(date -v1d '+%Y-%m-%d')
LAST_MONTH_START=$(date -v-1m -v1d '+%Y-%m-%d')
LAST_MONTH_END=$(date -v1d '+%Y-%m-%d')
TWO_MONTHS_AGO=$(date -v-2m -v1d '+%Y-%m-%d')

echo "Comparing costs:"
echo "- Two months ago: $TWO_MONTHS_AGO to $LAST_MONTH_START"
echo "- Last month: $LAST_MONTH_START to $LAST_MONTH_END"
echo ""

# Get cost comparison by service
echo "Cost Comparison by Service (Last 2 Months):"
echo "============================================"

# Get costs for both months separately
echo "Month 1 ($TWO_MONTHS_AGO to $LAST_MONTH_START):"
aws ce get-cost-and-usage \
    --time-period Start=$TWO_MONTHS_AGO,End=$LAST_MONTH_START \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE \
    $PROFILE \
    --query 'ResultsByTime[0].Groups[*].[Keys[0],Metrics.BlendedCost.Amount]' \
    --output text | \
    awk 'NF==2 && $2>0 {printf "%-30s: $%.2f\n", $1, $2}' | \
    sort -k2 -nr | head -10

echo ""
echo "Month 2 ($LAST_MONTH_START to $LAST_MONTH_END):"
aws ce get-cost-and-usage \
    --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE \
    $PROFILE \
    --query 'ResultsByTime[0].Groups[*].[Keys[0],Metrics.BlendedCost.Amount]' \
    --output text | \
    awk 'NF==2 && $2>0 {printf "%-30s: $%.2f\n", $1, $2}' | \
    sort -k2 -nr | head -10

echo ""
echo "Top Cost Services (Current Month):"
echo "=================================="

aws ce get-cost-and-usage \
    --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE \
    $PROFILE \
    --query 'ResultsByTime[0].Groups[*].[Keys[0],Metrics.BlendedCost.Amount]' \
    --output text | \
    awk 'NF==2 && $2>0 {printf "%-30s: $%.2f\n", $1, $2}' | \
    sort -k2 -nr | head -10

echo ""
echo "Daily Cost Trend (Last 30 Days):"
echo "================================="

aws ce get-cost-and-usage \
    --time-period Start=$(date -v-30d '+%Y-%m-%d'),End=$(date '+%Y-%m-%d') \
    --granularity DAILY \
    --metrics BlendedCost \
    $PROFILE \
    --query 'ResultsByTime[-10:].[TimePeriod.Start,Total.BlendedCost.Amount]' \
    --output text | \
    awk '{printf "%s: $%.2f\n", $1, $2}'

echo ""
echo "Quick Resource Check:"
echo "===================="

# Check for unassociated Elastic IPs
echo "Unassociated Elastic IPs (cost: \$3.60/month each):"
unassociated_eips=$(aws ec2 describe-addresses $PROFILE --query 'Addresses[?InstanceId==null].AllocationId' --output text | wc -w)
echo "Count: $unassociated_eips"

# Check running instances
echo ""
echo "Running EC2 Instances:"
aws ec2 describe-instances $PROFILE \
    --query 'Reservations[*].Instances[?State.Name==`running`].[InstanceId,InstanceType,LaunchTime]' \
    --output text | \
    awk '{printf "%s (%s) - launched %s\n", $1, $2, $3}' | head -10

echo ""
echo "Recommendations:"
echo "================"
echo "1. Run individual service scripts to get detailed analysis:"
echo "   ./lambda/check_lambda_costs.sh"
echo "   ./s3/check_s3_costs.sh"
echo "   ./vpc/check_vpc_costs.sh"
echo ""
echo "2. Check for:"
echo "   - New resources launched recently"
echo "   - Increased usage patterns"
echo "   - Data transfer spikes"
echo "   - Unassociated Elastic IPs"
echo ""
echo "3. Use AWS Cost Anomaly Detection for automated alerts"