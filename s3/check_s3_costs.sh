#!/bin/bash

# Script to check AWS S3 costs by region
# Usage: ./check_s3_costs.sh [--profile profile_name] [region]

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

echo "S3 Cost Analysis - Region: $REGION (Last Month: $LAST_MONTH_START to $LAST_MONTH_END)"
echo "================================================================================"

# Get actual S3 costs from Cost Explorer
ACTUAL_COST=$(aws ce get-cost-and-usage \
    --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE \
    --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Simple Storage Service"]}}' \
    $PROFILE \
    --query 'ResultsByTime[*].Groups[?Keys[0]==`Amazon Simple Storage Service`].Metrics.BlendedCost.Amount' \
    --output text | awk '{print $1}')

echo "Actual Total S3 Cost from Cost Explorer: \$${ACTUAL_COST:-0.00}"
echo ""

# Get S3 cost breakdown by usage type
echo "S3 Cost Breakdown by Usage Type:"
echo "--------------------------------"

aws ce get-cost-and-usage \
    --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=USAGE_TYPE \
    --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Simple Storage Service"]}}' \
    $PROFILE \
    --query 'ResultsByTime[*].Groups[*].[Keys[0],Metrics.BlendedCost.Amount]' \
    --output text 2>/dev/null | \
    awk 'NF==2 && $2>0 {printf "%-50s $%.4f\n", $1, $2}' | \
    sort -k2 -nr

echo ""
echo "S3 Buckets Analysis:"
echo "===================="

# Find longest bucket name for formatting
MAX_LENGTH=$(aws s3api list-buckets $PROFILE --query 'Buckets[*].Name' --output text | tr '\t' '\n' | awk '{if(length > max) max = length} END {print max+5}')

if [ -z "$MAX_LENGTH" ] || [ "$MAX_LENGTH" -lt 30 ]; then
    MAX_LENGTH=40
fi

# Create table header
printf "+%*s+---------------+---------------+------------------+\n" $MAX_LENGTH | tr ' ' '-'
printf "| %-*s | Size (GB)     | Objects       | Est. Monthly Cost |\n" $MAX_LENGTH "Bucket Name"
printf "+%*s+---------------+---------------+------------------+\n" $MAX_LENGTH | tr ' ' '-'

# Get bucket details
for bucket in $(aws s3api list-buckets $PROFILE --query 'Buckets[*].Name' --output text); do
    # Get bucket region
    bucket_region=$(aws s3api get-bucket-location --bucket $bucket $PROFILE --query 'LocationConstraint' --output text 2>/dev/null)
    
    # Skip if bucket is not in the specified region (unless region is us-east-1/null)
    if [ "$bucket_region" != "$REGION" ] && [ "$bucket_region" != "None" ] && [ "$REGION" != "us-east-1" ]; then
        continue
    fi
    
    # Get bucket size using S3 API (more reliable than CloudWatch)
    printf "\rAnalyzing bucket: %-50s" "$bucket..." >&2
    
    # Use aws s3 ls to get total size
    bucket_info=$(aws s3 ls s3://$bucket --recursive --human-readable --summarize $PROFILE 2>/dev/null | tail -2)
    
    # Extract size and object count from summary
    size_line=$(echo "$bucket_info" | grep "Total Size:" | awk '{print $3, $4}')
    objects_line=$(echo "$bucket_info" | grep "Total Objects:" | awk '{print $3}')
    
    # Convert size to GB
    if [[ "$size_line" == *"TiB"* ]]; then
        size_value=$(echo "$size_line" | awk '{print $1}')
        size_gb=$(echo "$size_value" | awk '{printf "%.2f", $1 * 1024}')
    elif [[ "$size_line" == *"GiB"* ]]; then
        size_gb=$(echo "$size_line" | awk '{printf "%.2f", $1}')
    elif [[ "$size_line" == *"MiB"* ]]; then
        size_value=$(echo "$size_line" | awk '{print $1}')
        size_gb=$(echo "$size_value" | awk '{printf "%.2f", $1 / 1024}')
    elif [[ "$size_line" == *"KiB"* ]]; then
        size_value=$(echo "$size_line" | awk '{print $1}')
        size_gb=$(echo "$size_value" | awk '{printf "%.2f", $1 / 1024 / 1024}')
    else
        size_gb="0.00"
    fi
    
    # Get object count
    if [ -z "$objects_line" ]; then
        objects_line="0"
    fi
    
    # Estimate cost (Standard storage: $0.023 per GB/month)
    storage_cost=$(echo "$size_gb" | awk '{printf "%.4f", $1 * 0.023}')
    
    # Clear the progress line and print table row
    printf "\r%-70s\r" "" >&2
    printf "| %-*s | %-13s | %-13s | \$%-15s |\n" $MAX_LENGTH "$bucket" "$size_gb" "$objects_line" "$storage_cost"
done

# Close table
printf "\r%-70s\r" "" >&2
printf "+%*s+---------------+---------------+------------------+\n" $MAX_LENGTH | tr ' ' '-'

echo ""
echo "S3 Pricing Guide (us-east-1):"
echo "============================="
echo "Standard Storage:"
echo "  First 50 TB: \$0.023 per GB/month"
echo "  Next 450 TB: \$0.022 per GB/month"
echo "  Over 500 TB: \$0.021 per GB/month"
echo ""
echo "Infrequent Access (IA):"
echo "  Storage: \$0.0125 per GB/month"
echo "  Retrieval: \$0.01 per GB"
echo ""
echo "Glacier:"
echo "  Storage: \$0.004 per GB/month"
echo "  Retrieval: \$0.01 per GB (standard)"
echo ""
echo "Requests:"
echo "  PUT/POST: \$0.0005 per 1,000 requests"
echo "  GET/HEAD: \$0.0004 per 1,000 requests"
echo ""
echo "Cost Optimization Tips:"
echo "======================="
echo "1. Use S3 Intelligent Tiering for automatic cost optimization"
echo "2. Move old data to IA or Glacier storage classes"
echo "3. Enable S3 lifecycle policies"
echo "4. Delete incomplete multipart uploads"
echo "5. Use S3 Storage Class Analysis to identify optimization opportunities"