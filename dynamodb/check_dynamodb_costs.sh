#!/bin/bash

# Script to check AWS DynamoDB costs by region
# Usage: ./check_dynamodb_costs.sh [--profile profile_name] [region]

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

# Get actual DynamoDB costs from Cost Explorer
ACTUAL_COST=$(aws ce get-cost-and-usage \
    --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE \
    --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon DynamoDB"]}}' \
    $PROFILE \
    --query 'ResultsByTime[*].Groups[?Keys[0]==`Amazon DynamoDB`].Metrics.BlendedCost.Amount' \
    --output text | awk '{print $1}')

echo "DynamoDB Analysis - Region: $REGION (Last Month: $LAST_MONTH_START to $LAST_MONTH_END)"
echo "Actual Total Cost from Cost Explorer: \$$ACTUAL_COST"
echo ""

# Get cost breakdown by usage type
echo "DynamoDB Cost Breakdown by Usage Type:"
echo "-------------------------------------"
aws ce get-cost-and-usage \
    --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=USAGE_TYPE \
    --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon DynamoDB"]}}' \
    $PROFILE \
    --query 'ResultsByTime[*].Groups[].[Keys[0],Metrics.BlendedCost.Amount]' \
    --output text | awk '$2 > 0 {printf "%-50s $%.4f\n", $1, $2}'

echo ""

# Check if there are any tables
TABLES=$(aws dynamodb list-tables --region $REGION $PROFILE --query 'TableNames' --output text 2>/dev/null)

if [ -z "$TABLES" ] || [ "$TABLES" = "None" ]; then
    echo "No DynamoDB tables found in region $REGION"
    exit 0
fi

echo "DynamoDB Tables Analysis:"
echo "========================"

# Find longest table name for formatting
MAX_LENGTH=$(echo "$TABLES" | tr '\t' '\n' | awk '{if(length > max) max = length} END {print max+5}')
if [ -z "$MAX_LENGTH" ] || [ "$MAX_LENGTH" -lt 20 ]; then
    MAX_LENGTH=25
fi

# Create table header
printf "+%*s+---------------+-------+---------------+----------------+-------------+\n" $MAX_LENGTH | tr ' ' '-'
printf "| %-*s | Billing Mode  | Status| Read/Write    | Item Count     | Est. Price  |\n" $MAX_LENGTH "Table Name"
printf "+%*s+---------------+-------+---------------+----------------+-------------+\n" $MAX_LENGTH | tr ' ' '-'

# Get table details
for table in $TABLES; do
    table_info=$(aws dynamodb describe-table \
        --table-name "$table" \
        --region $REGION \
        $PROFILE \
        --query 'Table.[BillingModeSummary.BillingMode,TableStatus,ProvisionedThroughput.ReadCapacityUnits,ProvisionedThroughput.WriteCapacityUnits,ItemCount]' \
        --output text 2>/dev/null)
    
    if [ -n "$table_info" ]; then
        billing_mode=$(echo "$table_info" | awk '{print $1}')
        status=$(echo "$table_info" | awk '{print $2}')
        read_capacity=$(echo "$table_info" | awk '{print $3}')
        write_capacity=$(echo "$table_info" | awk '{print $4}')
        item_count=$(echo "$table_info" | awk '{print $5}')
        
        # Fix billing mode display
        if [ "$billing_mode" = "None" ] || [ -z "$billing_mode" ]; then
            billing_mode="PAY_PER_REQUEST"
        fi
        
        # Handle different billing modes
        if [ "$billing_mode" = "PROVISIONED" ]; then
            if [ "$read_capacity" != "None" ] && [ "$write_capacity" != "None" ]; then
                rw_capacity="${read_capacity}R/${write_capacity}W"
                # Estimate cost: RCU * $0.00013/hour + WCU * $0.00065/hour * 24 * 30
                monthly_cost=$(echo "$read_capacity $write_capacity" | awk '{printf "%.2f", ($1 * 0.00013 + $2 * 0.00065) * 24 * 30}')
            else
                rw_capacity="N/A"
                monthly_cost="N/A"
            fi
        else
            rw_capacity="On-Demand"
            # For On-Demand, estimate based on item count (very rough estimate)
            if [ "$item_count" != "None" ] && [ -n "$item_count" ] && [ "$item_count" -gt 0 ]; then
                # Rough estimate: $1.25 per million read requests, $1.25 per million write requests
                # Assume 1 read per item per month, minimal writes
                monthly_cost=$(echo "$item_count" | awk '{printf "%.2f", ($1 / 1000000) * 1.25 * 1.1}')
            else
                monthly_cost="<0.01"
            fi
        fi
        
        # Format item count
        if [ "$item_count" = "None" ] || [ -z "$item_count" ]; then
            item_count="Unknown"
        elif [ "$item_count" -gt 1000000 ]; then
            item_count=$(echo "$item_count" | awk '{printf "%.1fM", $1/1000000}')
        elif [ "$item_count" -gt 1000 ]; then
            item_count=$(echo "$item_count" | awk '{printf "%.1fK", $1/1000}')
        fi
        
        printf "| %-*s | %-13s | %-5s | %-13s | %-14s | \$%-10s |\n" $MAX_LENGTH "$table" "$billing_mode" "$status" "$rw_capacity" "$item_count" "$monthly_cost"
    fi
done

# Close table
printf "+%*s+---------------+-------+---------------+----------------+-------------+\n" $MAX_LENGTH | tr ' ' '-'

echo ""
echo "DynamoDB Global Tables:"
echo "======================"
GLOBAL_TABLES=$(aws dynamodb list-global-tables --region $REGION $PROFILE --query 'GlobalTables[*].GlobalTableName' --output text 2>/dev/null)
if [ -n "$GLOBAL_TABLES" ] && [ "$GLOBAL_TABLES" != "None" ]; then
    echo "Global Tables found: $(echo $GLOBAL_TABLES | wc -w)"
    for gt in $GLOBAL_TABLES; do
        echo "- $gt"
    done
else
    echo "No Global Tables found"
fi

echo ""
echo "Additional DynamoDB Components:"
echo "=============================="

# Check for backups
BACKUPS=$(aws dynamodb list-backups --region $REGION $PROFILE --query 'BackupSummaries[?BackupStatus==`AVAILABLE`]' --output text 2>/dev/null | wc -l)
echo "Backups: $BACKUPS available backups"
echo "- On-demand backups are charged per GB stored"
echo "- Point-in-time recovery (PITR) is charged per GB-month"

# Check for streams
echo ""
echo "DynamoDB Streams:"
STREAM_COUNT=0
for table in $TABLES; do
    STREAM=$(aws dynamodb describe-table \
        --table-name "$table" \
        --region $REGION \
        $PROFILE \
        --query 'Table.StreamSpecification.StreamEnabled' \
        --output text 2>/dev/null)
    if [ "$STREAM" = "True" ]; then
        STREAM_COUNT=$((STREAM_COUNT + 1))
    fi
done
echo "- Tables with streams enabled: $STREAM_COUNT"
echo "- Streams are charged per 100,000 read requests"

echo ""
echo "Cost Optimization Tips:"
echo "======================"
echo "• Use On-Demand billing for unpredictable workloads"
echo "• Use Provisioned billing with Auto Scaling for predictable workloads"
echo "• Enable DynamoDB Contributor Insights to identify hot partitions"
echo "• Use DynamoDB Accelerator (DAX) for microsecond latency requirements"
echo "• Implement efficient query patterns to reduce RCU/WCU consumption"
echo "• Use Global Secondary Indexes (GSI) sparingly and optimize projections"
echo "• Consider DynamoDB Standard-IA for infrequently accessed data"
echo "• Set up lifecycle policies for backups to manage storage costs"