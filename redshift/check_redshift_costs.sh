#!/bin/bash

# Script to check AWS Redshift costs by region
# Usage: ./check_redshift_costs.sh [--profile profile_name] [region]

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

# Get actual Redshift costs from Cost Explorer
ACTUAL_COST=$(aws ce get-cost-and-usage \
    --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE \
    --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Redshift"]}}' \
    $PROFILE \
    --query 'ResultsByTime[*].Groups[?Keys[0]==`Amazon Redshift`].Metrics.BlendedCost.Amount' \
    --output text | awk '{print $1}')

echo "Redshift Cluster Analysis - Region: $REGION (Last Month: $LAST_MONTH_START to $LAST_MONTH_END)"
echo "Actual Total Cost from Cost Explorer: \$$ACTUAL_COST"
echo ""

# Get cost breakdown by usage type
echo "Redshift Cost Breakdown by Usage Type:"
echo "-------------------------------------"
aws ce get-cost-and-usage \
    --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=USAGE_TYPE \
    --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Redshift"]}}' \
    $PROFILE \
    --query 'ResultsByTime[*].Groups[].[Keys[0],Metrics.BlendedCost.Amount]' \
    --output text | awk '$2 > 0 {printf "%-50s $%.4f\n", $1, $2}'

echo ""

# Check if there are any clusters
CLUSTERS=$(aws redshift describe-clusters --region $REGION $PROFILE --query 'Clusters[*].ClusterIdentifier' --output text 2>/dev/null)

if [ -z "$CLUSTERS" ] || [ "$CLUSTERS" = "None" ]; then
    echo "No Redshift clusters found in region $REGION"
    exit 0
fi

echo "Redshift Clusters Analysis:"
echo "=========================="

# Find longest cluster name for formatting
MAX_LENGTH=$(echo "$CLUSTERS" | tr '\t' '\n' | awk '{if(length > max) max = length} END {print max+5}')
if [ -z "$MAX_LENGTH" ] || [ "$MAX_LENGTH" -lt 20 ]; then
    MAX_LENGTH=25
fi

# Create table header
printf "+%*s+---------------+-------+---------------+----------------+-------------+-------------+\n" $MAX_LENGTH | tr ' ' '-'
printf "| %-*s | Node Type     | Nodes | Status        | Created        | Est. Price  | RI Status   |\n" $MAX_LENGTH "Cluster Identifier"
printf "+%*s+---------------+-------+---------------+----------------+-------------+-------------+\n" $MAX_LENGTH | tr ' ' '-'

# Get cluster details
for cluster in $CLUSTERS; do
    cluster_info=$(aws redshift describe-clusters \
        --cluster-identifier "$cluster" \
        --region $REGION \
        $PROFILE \
        --query 'Clusters[0].[NodeType,NumberOfNodes,ClusterStatus,ClusterCreateTime]' \
        --output text 2>/dev/null)
    
    if [ -n "$cluster_info" ]; then
        node_type=$(echo "$cluster_info" | awk '{print $1}')
        num_nodes=$(echo "$cluster_info" | awk '{print $2}')
        status=$(echo "$cluster_info" | awk '{print $3}')
        created=$(echo "$cluster_info" | awk '{print $4}' | cut -d'T' -f1)
        
        # Estimate monthly cost based on node type (approximate pricing)
        case $node_type in
            dc2.large)
                hourly_cost=$(echo "$num_nodes" | awk '{print $1 * 0.25}')
                ;;
            dc2.8xlarge)
                hourly_cost=$(echo "$num_nodes" | awk '{print $1 * 4.80}')
                ;;
            ds2.xlarge)
                hourly_cost=$(echo "$num_nodes" | awk '{print $1 * 0.85}')
                ;;
            ds2.8xlarge)
                hourly_cost=$(echo "$num_nodes" | awk '{print $1 * 6.80}')
                ;;
            ra3.xlplus)
                hourly_cost=$(echo "$num_nodes" | awk '{print $1 * 1.086}')
                ;;
            ra3.4xlarge)
                hourly_cost=$(echo "$num_nodes" | awk '{print $1 * 3.26}')
                ;;
            ra3.16xlarge)
                hourly_cost=$(echo "$num_nodes" | awk '{print $1 * 13.04}')
                ;;
            *)
                hourly_cost="Unknown"
                ;;
        esac
        
        if [ "$hourly_cost" != "Unknown" ]; then
            monthly_cost=$(echo "$hourly_cost" | awk '{printf "%.2f", $1 * 24 * 30}')
        else
            monthly_cost="N/A"
        fi
        
        # Check for Reserved Instances
        ri_status="On-Demand"
        ri_info=$(aws redshift describe-reserved-nodes \
            --region $REGION \
            $PROFILE \
            --query "ReservedNodes[?NodeType=='$node_type' && State=='active'].{Count:NodeCount,Type:OfferingType}" \
            --output text 2>/dev/null)
        
        if [ -n "$ri_info" ] && [ "$ri_info" != "None" ]; then
            ri_count=$(echo "$ri_info" | awk '{sum+=$1} END {print sum}')
            ri_type=$(echo "$ri_info" | awk '{print $2}' | head -1)
            if [ "$ri_count" -ge "$num_nodes" ]; then
                ri_status="$ri_type RI"
                # Apply RI discount (approximate 25-75% savings)
                monthly_cost=$(echo "$monthly_cost" | awk '{printf "%.2f", $1 * 0.5}')
            else
                ri_status="Partial RI"
            fi
        fi
        
        printf "| %-*s | %-13s | %-5s | %-13s | %-14s | \$%-10s | %-11s |\n" $MAX_LENGTH "$cluster" "$node_type" "$num_nodes" "$status" "$created" "$monthly_cost" "$ri_status"
    fi
done

# Close table
printf "+%*s+---------------+-------+---------------+----------------+-------------+-------------+\n" $MAX_LENGTH | tr ' ' '-'

echo ""
echo "Reserved Instances Summary:"
echo "=========================="
aws redshift describe-reserved-nodes \
    --region $REGION \
    $PROFILE \
    --query 'ReservedNodes[?State==`active`].[NodeType,NodeCount,OfferingType,Duration,FixedPrice,UsagePrice]' \
    --output table 2>/dev/null || echo "No active Reserved Instances found"

echo ""
echo "Additional Redshift Components:"
echo "==============================="

# Check for Redshift Spectrum usage
echo "Redshift Spectrum:"
echo "- Check CloudWatch metrics for Spectrum query execution"
echo "- Spectrum charges per TB of data scanned"

# Check for backup storage
echo ""
echo "Backup Storage:"
echo "- Automated backups are free up to 100% of cluster storage"
echo "- Manual snapshots and backups beyond 100% incur charges"

# Get snapshot information
SNAPSHOTS=$(aws redshift describe-cluster-snapshots \
    --region $REGION \
    $PROFILE \
    --query 'Snapshots[?SnapshotType==`manual`].[SnapshotIdentifier,TotalBackupSizeInMegaBytes]' \
    --output text 2>/dev/null | wc -l)

if [ "$SNAPSHOTS" -gt 0 ]; then
    echo "- Manual snapshots found: $SNAPSHOTS"
    echo "- Manual snapshot storage is charged at standard S3 rates"
fi

echo ""
echo "Cost Optimization Tips:"
echo "======================"
echo "• Use Reserved Instances for predictable workloads (up to 75% savings)"
echo "• Consider pausing clusters during non-business hours"
echo "• Use RA3 nodes with managed storage for better cost efficiency"
echo "• Monitor and optimize query performance to reduce compute time"
echo "• Use Redshift Spectrum for infrequently accessed data"
echo "• Set up automated snapshots retention policies"