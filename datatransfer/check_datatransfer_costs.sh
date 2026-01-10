#!/bin/bash

# Script to check AWS Data Transfer costs by region
# Usage: ./check_datatransfer_costs.sh [--profile profile_name] [region]

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

echo "Data Transfer Cost Analysis - Region: $REGION (Last Month: $LAST_MONTH_START to $LAST_MONTH_END)"
echo "========================================================================================="

# Get data transfer costs from Cost Explorer
echo "Data Transfer Costs by Service:"
echo "------------------------------"

aws ce get-cost-and-usage \
    --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=USAGE_TYPE \
    --filter '{"Or":[{"Dimensions":{"Key":"USAGE_TYPE","Values":["DataTransfer-Out-Bytes","DataTransfer-In-Bytes","DataTransfer-Regional-Bytes"]}},{"Dimensions":{"Key":"USAGE_TYPE_GROUP","Values":["EC2-Data Transfer"]}}]}' \
    $PROFILE \
    --query 'ResultsByTime[*].Groups[*].[Keys[0],Metrics.BlendedCost.Amount]' \
    --output text 2>/dev/null | \
    awk 'NF==2 && $2>0 {printf "%-50s $%.4f\n", $1, $2}' | \
    sort -k2 -nr

echo ""
echo "CloudFront Data Transfer:"
echo "------------------------"

# Get CloudFront costs
aws ce get-cost-and-usage \
    --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=USAGE_TYPE \
    --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon CloudFront"]}}' \
    $PROFILE \
    --query 'ResultsByTime[*].Groups[*].[Keys[0],Metrics.BlendedCost.Amount]' \
    --output text 2>/dev/null | \
    awk 'NF==2 && $2>0 {printf "%-50s $%.4f\n", $1, $2}' | \
    sort -k2 -nr

echo ""
echo "NAT Gateway Data Processing:"
echo "---------------------------"

# Get NAT Gateway data processing costs
aws ce get-cost-and-usage \
    --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=USAGE_TYPE \
    --filter '{"And":[{"Dimensions":{"Key":"SERVICE","Values":["Amazon Elastic Compute Cloud - Compute"]}},{"Dimensions":{"Key":"USAGE_TYPE","Values":["NatGateway-Bytes"]}}]}' \
    $PROFILE \
    --query 'ResultsByTime[*].Groups[*].[Keys[0],Metrics.BlendedCost.Amount]' \
    --output text 2>/dev/null | \
    awk 'NF==2 && $2>0 {printf "%-50s $%.4f\n", $1, $2}' | \
    sort -k2 -nr

echo ""
echo "Data Transfer Metrics (CloudWatch):"
echo "====================================="

# Get EC2 network metrics
echo "EC2 Network Out (Top 10 instances):"
echo "-----------------------------------"

for instance in $(aws ec2 describe-instances --region $REGION $PROFILE --query 'Reservations[*].Instances[?State.Name==`running`].InstanceId' --output text | head -10); do
    bytes_out=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/EC2 \
        --metric-name NetworkOut \
        --dimensions Name=InstanceId,Value=$instance \
        --start-time "${LAST_MONTH_START}T00:00:00Z" \
        --end-time "${LAST_MONTH_END}T00:00:00Z" \
        --period 2592000 \
        --statistics Sum \
        --region $REGION \
        $PROFILE \
        --query 'Datapoints[0].Sum' \
        --output text 2>/dev/null)
    
    if [ -n "$bytes_out" ] && [ "$bytes_out" != "None" ] && [ "$bytes_out" != "0" ]; then
        gb_out=$(echo "$bytes_out" | awk '{printf "%.2f", $1/1024/1024/1024}')
        echo "$instance: ${gb_out} GB"
    fi
done

echo ""
echo "Data Transfer Pricing Guide:"
echo "============================"
echo "Internet Data Transfer Out:"
echo "  First 1 GB/month: Free"
echo "  Next 9.999 TB/month: \$0.09 per GB"
echo "  Next 40 TB/month: \$0.085 per GB"
echo "  Next 100 TB/month: \$0.07 per GB"
echo "  Over 150 TB/month: \$0.05 per GB"
echo ""
echo "Regional Data Transfer:"
echo "  Same AZ: Free"
echo "  Different AZ: \$0.01 per GB in/out"
echo "  Different Region: \$0.02 per GB out"
echo ""
echo "NAT Gateway:"
echo "  Data processing: \$0.045 per GB"
echo ""
echo "CloudFront:"
echo "  Varies by region: \$0.085-\$0.25 per GB"
echo ""
echo "Cost Optimization Tips:"
echo "======================="
echo "1. Use CloudFront for static content (cheaper than EC2 data transfer)"
echo "2. Keep resources in same AZ when possible"
echo "3. Use VPC Endpoints for AWS services"
echo "4. Monitor and optimize large data transfers"
echo "5. Consider AWS Direct Connect for high volume transfers"