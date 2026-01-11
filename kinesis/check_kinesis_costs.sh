#!/bin/bash

# Script to check AWS Kinesis costs by region
# Usage: ./check_kinesis_costs.sh [--profile profile_name] [region]

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

# Get actual Kinesis costs from Cost Explorer
ACTUAL_COST=$(aws ce get-cost-and-usage \
    --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE \
    --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Kinesis","Amazon Kinesis Firehose","Amazon Kinesis Analytics"]}}' \
    $PROFILE \
    --query 'ResultsByTime[*].Groups[].[Keys[0],Metrics.BlendedCost.Amount]' \
    --output text | awk '{sum+=$2} END {printf "%.2f", sum}')

echo "Kinesis Services Analysis - Region: $REGION (Last Month: $LAST_MONTH_START to $LAST_MONTH_END)"
echo "Actual Total Cost from Cost Explorer: \$$ACTUAL_COST"
echo ""

# Get cost breakdown by service and usage type
echo "Kinesis Cost Breakdown by Service:"
echo "---------------------------------"
aws ce get-cost-and-usage \
    --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE \
    --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Kinesis","Amazon Kinesis Firehose","Amazon Kinesis Analytics"]}}' \
    $PROFILE \
    --query 'ResultsByTime[*].Groups[].[Keys[0],Metrics.BlendedCost.Amount]' \
    --output text | awk '$2 > 0 {printf "%-40s $%.4f\n", $1, $2}'

echo ""
echo "Kinesis Cost Breakdown by Usage Type:"
echo "------------------------------------"
aws ce get-cost-and-usage \
    --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=USAGE_TYPE \
    --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Kinesis","Amazon Kinesis Firehose","Amazon Kinesis Analytics"]}}' \
    $PROFILE \
    --query 'ResultsByTime[*].Groups[].[Keys[0],Metrics.BlendedCost.Amount]' \
    --output text | awk '$2 > 0 {printf "%-50s $%.4f\n", $1, $2}'

echo ""

# Check Kinesis Data Streams
echo "Kinesis Data Streams Analysis:"
echo "============================="
STREAMS=$(aws kinesis list-streams --region $REGION $PROFILE --query 'StreamNames' --output text 2>/dev/null)

if [ -n "$STREAMS" ] && [ "$STREAMS" != "None" ]; then
    # Find longest stream name for formatting
    MAX_LENGTH=$(echo "$STREAMS" | tr '\t' '\n' | awk '{if(length > max) max = length} END {print max+5}')
    if [ -z "$MAX_LENGTH" ] || [ "$MAX_LENGTH" -lt 20 ]; then
        MAX_LENGTH=25
    fi

    # Create table header
    printf "+%*s+-------+--------+------------------+----------------+-------------+\n" $MAX_LENGTH | tr ' ' '-'
    printf "| %-*s | Shards| Status | Retention        | Encryption     | Est. Price  |\n" $MAX_LENGTH "Stream Name"
    printf "+%*s+-------+--------+------------------+----------------+-------------+\n" $MAX_LENGTH | tr ' ' '-'

    for stream in $STREAMS; do
        stream_info=$(aws kinesis describe-stream \
            --stream-name "$stream" \
            --region $REGION \
            $PROFILE \
            --query 'StreamDescription.[StreamStatus,RetentionPeriodHours,EncryptionType]' \
            --output text 2>/dev/null)
        
        # Get shard count separately
        shard_count=$(aws kinesis describe-stream \
            --stream-name "$stream" \
            --region $REGION \
            $PROFILE \
            --query 'length(StreamDescription.Shards)' \
            --output text 2>/dev/null)
        
        if [ -n "$stream_info" ] && [ -n "$shard_count" ]; then
            status=$(echo "$stream_info" | awk '{print $1}')
            retention=$(echo "$stream_info" | awk '{print $2}')
            encryption=$(echo "$stream_info" | awk '{print $3}')
            
            # Estimate monthly cost: $0.015 per shard hour
            monthly_cost=$(echo "$shard_count" | awk '{printf "%.2f", $1 * 0.015 * 24 * 30}')
            
            # Format retention
            if [ "$retention" -gt 24 ] 2>/dev/null; then
                retention_display="${retention}h (Extended)"
            else
                retention_display="${retention}h (Standard)"
            fi
            
            # Format encryption
            if [ "$encryption" = "None" ] || [ -z "$encryption" ]; then
                encryption_display="None"
            else
                encryption_display="$encryption"
            fi
            
            printf "| %-*s | %-5s | %-6s | %-16s | %-14s | \$%-10s |\n" $MAX_LENGTH "$stream" "$shard_count" "$status" "$retention_display" "$encryption_display" "$monthly_cost"
        fi
    done
    
    # Close table
    printf "+%*s+-------+--------+------------------+----------------+-------------+\n" $MAX_LENGTH | tr ' ' '-'
else
    echo "No Kinesis Data Streams found in region $REGION"
fi

echo ""

# Check Kinesis Data Firehose
echo "Kinesis Data Firehose Analysis:"
echo "=============================="
FIREHOSE_STREAMS=$(aws firehose list-delivery-streams --region $REGION $PROFILE --query 'DeliveryStreamNames' --output text 2>/dev/null)

if [ -n "$FIREHOSE_STREAMS" ] && [ "$FIREHOSE_STREAMS" != "None" ]; then
    # Find longest stream name for formatting
    MAX_LENGTH=$(echo "$FIREHOSE_STREAMS" | tr '\t' '\n' | awk '{if(length > max) max = length} END {print max+5}')
    if [ -z "$MAX_LENGTH" ] || [ "$MAX_LENGTH" -lt 20 ]; then
        MAX_LENGTH=25
    fi

    # Create table header
    printf "+%*s+--------+---------------+----------------+-------------+\n" $MAX_LENGTH | tr ' ' '-'
    printf "| %-*s | Status | Destination   | Compression    | Est. Price  |\n" $MAX_LENGTH "Delivery Stream"
    printf "+%*s+--------+---------------+----------------+-------------+\n" $MAX_LENGTH | tr ' ' '-'

    for stream in $FIREHOSE_STREAMS; do
        stream_info=$(aws firehose describe-delivery-stream \
            --delivery-stream-name "$stream" \
            --region $REGION \
            $PROFILE \
            --query 'DeliveryStreamDescription.[DeliveryStreamStatus,Destinations[0].S3DestinationDescription.CompressionFormat,Destinations[0].ExtendedS3DestinationDescription.CompressionFormat]' \
            --output text 2>/dev/null)
        
        if [ -n "$stream_info" ]; then
            status=$(echo "$stream_info" | awk '{print $1}')
            compression1=$(echo "$stream_info" | awk '{print $2}')
            compression2=$(echo "$stream_info" | awk '{print $3}')
            
            # Determine compression
            if [ "$compression1" != "None" ] && [ -n "$compression1" ]; then
                compression="$compression1"
            elif [ "$compression2" != "None" ] && [ -n "$compression2" ]; then
                compression="$compression2"
            else
                compression="None"
            fi
            
            # Estimate cost: $0.029 per GB ingested (first 500TB/month)
            # This is a base estimate - actual cost depends on data volume
            monthly_cost="Variable"
            
            printf "| %-*s | %-6s | %-13s | %-14s | \$%-10s |\n" $MAX_LENGTH "$stream" "$status" "S3/Other" "$compression" "$monthly_cost"
        fi
    done
    
    # Close table
    printf "+%*s+--------+---------------+----------------+-------------+\n" $MAX_LENGTH | tr ' ' '-'
else
    echo "No Kinesis Data Firehose delivery streams found in region $REGION"
fi

echo ""

# Check Kinesis Analytics (v1 and v2)
echo "Kinesis Analytics Applications:"
echo "=============================="
ANALYTICS_APPS=$(aws kinesisanalytics list-applications --region $REGION $PROFILE --query 'ApplicationSummaries[*].ApplicationName' --output text 2>/dev/null)
ANALYTICS_V2_APPS=$(aws kinesisanalyticsv2 list-applications --region $REGION $PROFILE --query 'ApplicationSummaries[*].ApplicationName' --output text 2>/dev/null)

if [ -n "$ANALYTICS_APPS" ] && [ "$ANALYTICS_APPS" != "None" ]; then
    echo "Kinesis Analytics v1 Applications:"
    for app in $ANALYTICS_APPS; do
        app_info=$(aws kinesisanalytics describe-application \
            --application-name "$app" \
            --region $REGION \
            $PROFILE \
            --query 'ApplicationDetail.[ApplicationStatus,CreateTimestamp]' \
            --output text 2>/dev/null)
        
        if [ -n "$app_info" ]; then
            status=$(echo "$app_info" | awk '{print $1}')
            created=$(echo "$app_info" | awk '{print $2}' | cut -d'T' -f1)
            echo "- $app (Status: $status, Created: $created)"
        fi
    done
fi

if [ -n "$ANALYTICS_V2_APPS" ] && [ "$ANALYTICS_V2_APPS" != "None" ]; then
    echo "Kinesis Analytics v2 Applications:"
    for app in $ANALYTICS_V2_APPS; do
        app_info=$(aws kinesisanalyticsv2 describe-application \
            --application-name "$app" \
            --region $REGION \
            $PROFILE \
            --query 'ApplicationDetail.[ApplicationStatus,CreateTimestamp]' \
            --output text 2>/dev/null)
        
        if [ -n "$app_info" ]; then
            status=$(echo "$app_info" | awk '{print $1}')
            created=$(echo "$app_info" | awk '{print $2}' | cut -d'T' -f1)
            echo "- $app (Status: $status, Created: $created)"
        fi
    done
fi

if [ -z "$ANALYTICS_APPS" ] && [ -z "$ANALYTICS_V2_APPS" ]; then
    echo "No Kinesis Analytics applications found in region $REGION"
fi

echo ""
echo "Kinesis Pricing Summary:"
echo "======================="
echo "Data Streams:"
echo "- Shard Hour: \$0.015 per shard per hour"
echo "- PUT Payload Units: \$0.014 per million units"
echo "- Extended Data Retention: \$0.023 per shard hour (beyond 24 hours)"
echo ""
echo "Data Firehose:"
echo "- Data Ingestion: \$0.029 per GB (first 500 TB/month)"
echo "- Format Conversion: \$0.018 per GB converted"
echo ""
echo "Analytics:"
echo "- Kinesis Processing Unit (KPU): \$0.11 per hour"
echo "- Running applications are charged per KPU hour"

echo ""
echo "Cost Optimization Tips:"
echo "======================"
echo "• Right-size the number of shards based on actual throughput needs"
echo "• Use data compression in Firehose to reduce ingestion costs"
echo "• Monitor shard utilization and merge under-utilized shards"
echo "• Set appropriate data retention periods (default 24h is often sufficient)"
echo "• Use Kinesis Scaling Utility for automatic shard scaling"
echo "• Consider batch processing for non-real-time use cases"
echo "• Monitor CloudWatch metrics to optimize shard count"