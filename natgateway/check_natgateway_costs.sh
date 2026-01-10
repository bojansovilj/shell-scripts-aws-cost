#!/bin/bash

# Script to check AWS NAT Gateway costs by region
# Usage: ./check_natgateway_costs.sh [--profile profile_name] [region]

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

echo "NAT Gateway Cost Analysis - Region: $REGION (Last Month: $LAST_MONTH_START to $LAST_MONTH_END)"
echo "==================================================================================="

# Get actual NAT Gateway costs from Cost Explorer
ACTUAL_COST=$(aws ce get-cost-and-usage \
    --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE \
    --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Elastic Compute Cloud - Compute"]}}' \
    $PROFILE \
    --query 'ResultsByTime[*].Groups[?Keys[0]==`Amazon Elastic Compute Cloud - Compute`].Metrics.BlendedCost.Amount' \
    --output text | awk '{print $1}')

echo "Total EC2 Cost (includes NAT Gateway): \$${ACTUAL_COST:-0.00}"
echo ""

# Get all NAT Gateways
echo "NAT Gateway Analysis:"
echo "--------------------"

# Find longest NAT Gateway ID for formatting
MAX_LENGTH=$(aws ec2 describe-nat-gateways --region $REGION $PROFILE --query 'NatGateways[*].NatGatewayId' --output text | tr '\t' '\n' | awk '{if(length > max) max = length} END {print max+5}')

if [ -z "$MAX_LENGTH" ] || [ "$MAX_LENGTH" -lt 20 ]; then
    MAX_LENGTH=25
fi

# Create table header
printf "+%*s+----------+---------------+----------------+-------------+\n" $MAX_LENGTH | tr ' ' '-'
printf "| %-*s | State    | Data Out (GB) | Hours Running  | Est. Cost   |\n" $MAX_LENGTH "NAT Gateway ID"
printf "+%*s+----------+---------------+----------------+-------------+\n" $MAX_LENGTH | tr ' ' '-'

# Get NAT Gateway details
for nat_id in $(aws ec2 describe-nat-gateways --region $REGION $PROFILE --query 'NatGateways[*].NatGatewayId' --output text); do
    # Get NAT Gateway state
    state=$(aws ec2 describe-nat-gateways --nat-gateway-ids $nat_id --region $REGION $PROFILE --query 'NatGateways[0].State' --output text)
    
    # Get data transfer metrics from CloudWatch
    bytes_out=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/NATGateway \
        --metric-name BytesOutToDestination \
        --dimensions Name=NatGatewayId,Value=$nat_id \
        --start-time "${LAST_MONTH_START}T00:00:00Z" \
        --end-time "${LAST_MONTH_END}T00:00:00Z" \
        --period 2592000 \
        --statistics Sum \
        --region $REGION \
        $PROFILE \
        --query 'Datapoints[0].Sum' \
        --output text 2>/dev/null)
    
    if [ -z "$bytes_out" ] || [ "$bytes_out" = "None" ]; then
        bytes_out=0
    fi
    
    # Convert bytes to GB
    gb_out=$(echo "$bytes_out" | awk '{printf "%.2f", $1/1024/1024/1024}')
    
    # Estimate hours running (assume 30 days if available)
    if [ "$state" = "available" ]; then
        hours_running=720  # 30 days * 24 hours
    else
        hours_running=0
    fi
    
    # Calculate estimated cost
    # NAT Gateway: $0.045/hour + $0.045/GB processed
    hourly_cost=$(echo "$hours_running" | awk '{printf "%.2f", $1 * 0.045}')
    data_cost=$(echo "$gb_out" | awk '{printf "%.2f", $1 * 0.045}')
    total_cost=$(echo "$hourly_cost $data_cost" | awk '{printf "%.2f", $1 + $2}')
    
    printf "| %-*s | %-8s | %-13s | %-14s | \$%-10s |\n" $MAX_LENGTH "$nat_id" "$state" "$gb_out" "$hours_running" "$total_cost"
done

# Close table
printf "+%*s+----------+---------------+----------------+-------------+\n" $MAX_LENGTH | tr ' ' '-'

echo ""
echo "NAT Gateway Pricing (us-east-1 rates):"
echo "--------------------------------------"
echo "Hourly charge: \$0.045 per hour"
echo "Data processing: \$0.045 per GB"
echo "Monthly cost per NAT Gateway: ~\$32.40 (if running 24/7)"
echo ""
echo "Cost Optimization Tips:"
echo "----------------------"
echo "1. Delete unused NAT Gateways"
echo "2. Use NAT Instances for lower traffic (cheaper but less managed)"
echo "3. Consider VPC Endpoints for AWS services to avoid NAT Gateway"
echo "4. Review data transfer patterns - high GB out = high costs"