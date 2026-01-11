#!/bin/bash

# Script to check AWS EC2 costs by region
# Usage: ./check_ec2_costs.sh [--profile profile_name] [region]

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

# Get actual EC2 costs from Cost Explorer
ACTUAL_COST=$(aws ce get-cost-and-usage \
    --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE \
    --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Elastic Compute Cloud - Compute"]}}' \
    $PROFILE \
    --query 'ResultsByTime[*].Groups[?Keys[0]==`Amazon Elastic Compute Cloud - Compute`].Metrics.BlendedCost.Amount' \
    --output text | awk '{print $1}')

echo "EC2 Instance Analysis - Region: $REGION (Last Month: $LAST_MONTH_START to $LAST_MONTH_END)"
echo "Actual Total Cost from Cost Explorer: \$$ACTUAL_COST"
echo ""

# Get cost breakdown by usage type
echo "EC2 Cost Breakdown by Usage Type:"
echo "---------------------------------"
aws ce get-cost-and-usage \
    --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=USAGE_TYPE \
    --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Elastic Compute Cloud - Compute"]}}' \
    $PROFILE \
    --query 'ResultsByTime[*].Groups[].[Keys[0],Metrics.BlendedCost.Amount]' \
    --output text | awk '$2 > 0 {printf "%-50s $%.4f\n", $1, $2}'

echo ""

# Check if there are any instances
INSTANCES=$(aws ec2 describe-instances --region $REGION $PROFILE --query 'Reservations[*].Instances[?State.Name!=`terminated`].InstanceId' --output text 2>/dev/null)

if [ -z "$INSTANCES" ] || [ "$INSTANCES" = "None" ]; then
    echo "No EC2 instances found in region $REGION"
    exit 0
fi

echo "EC2 Instances Analysis:"
echo "======================"

# Find longest instance name for formatting
MAX_LENGTH=25

# Create table header
printf "+%*s+---------------+-------+---------------+----------------+-------------+-------------+\n" $MAX_LENGTH | tr ' ' '-'
printf "| %-*s | Instance Type | State | AZ            | Launch Time    | Est. Price  | RI Status   |\n" $MAX_LENGTH "Instance ID"
printf "+%*s+---------------+-------+---------------+----------------+-------------+-------------+\n" $MAX_LENGTH | tr ' ' '-'

# Get instance details
aws ec2 describe-instances \
    --region $REGION \
    $PROFILE \
    --query 'Reservations[*].Instances[?State.Name!=`terminated`].[InstanceId,InstanceType,State.Name,Placement.AvailabilityZone,LaunchTime]' \
    --output text 2>/dev/null | while read instance_id instance_type state az launch_time; do
    
    if [ -n "$instance_id" ] && [ "$instance_id" != "None" ]; then
        launch_date=$(echo "$launch_time" | cut -d'T' -f1)
        
        # Estimate monthly cost based on instance type (approximate On-Demand pricing)
        case $instance_type in
            t2.nano)
                hourly_cost=0.0058
                ;;
            t2.micro)
                hourly_cost=0.0116
                ;;
            t2.small)
                hourly_cost=0.023
                ;;
            t2.medium)
                hourly_cost=0.0464
                ;;
            t2.large)
                hourly_cost=0.0928
                ;;
            t2.xlarge)
                hourly_cost=0.1856
                ;;
            t2.2xlarge)
                hourly_cost=0.3712
                ;;
            t3.nano)
                hourly_cost=0.0052
                ;;
            t3.micro)
                hourly_cost=0.0104
                ;;
            t3.small)
                hourly_cost=0.0208
                ;;
            t3.medium)
                hourly_cost=0.0416
                ;;
            t3.large)
                hourly_cost=0.0832
                ;;
            t3.xlarge)
                hourly_cost=0.1664
                ;;
            t3.2xlarge)
                hourly_cost=0.3328
                ;;
            t3a.nano)
                hourly_cost=0.0047
                ;;
            t3a.micro)
                hourly_cost=0.0094
                ;;
            t3a.small)
                hourly_cost=0.0188
                ;;
            t3a.medium)
                hourly_cost=0.0376
                ;;
            t3a.large)
                hourly_cost=0.0752
                ;;
            t3a.xlarge)
                hourly_cost=0.1504
                ;;
            t3a.2xlarge)
                hourly_cost=0.3008
                ;;
            m5.large)
                hourly_cost=0.096
                ;;
            m5.xlarge)
                hourly_cost=0.192
                ;;
            m5.2xlarge)
                hourly_cost=0.384
                ;;
            m5.4xlarge)
                hourly_cost=0.768
                ;;
            m5.8xlarge)
                hourly_cost=1.536
                ;;
            m5.12xlarge)
                hourly_cost=2.304
                ;;
            m5.16xlarge)
                hourly_cost=3.072
                ;;
            m5.24xlarge)
                hourly_cost=4.608
                ;;
            m5a.large)
                hourly_cost=0.086
                ;;
            m5a.xlarge)
                hourly_cost=0.172
                ;;
            m5a.2xlarge)
                hourly_cost=0.344
                ;;
            m5a.4xlarge)
                hourly_cost=0.688
                ;;
            c5.large)
                hourly_cost=0.085
                ;;
            c5.xlarge)
                hourly_cost=0.17
                ;;
            c5.2xlarge)
                hourly_cost=0.34
                ;;
            c5.4xlarge)
                hourly_cost=0.68
                ;;
            c5.9xlarge)
                hourly_cost=1.53
                ;;
            c5.12xlarge)
                hourly_cost=2.04
                ;;
            c5.18xlarge)
                hourly_cost=3.06
                ;;
            c5.24xlarge)
                hourly_cost=4.08
                ;;
            r5.large)
                hourly_cost=0.126
                ;;
            r5.xlarge)
                hourly_cost=0.252
                ;;
            r5.2xlarge)
                hourly_cost=0.504
                ;;
            r5.4xlarge)
                hourly_cost=1.008
                ;;
            r5.8xlarge)
                hourly_cost=2.016
                ;;
            r5.12xlarge)
                hourly_cost=3.024
                ;;
            r5.16xlarge)
                hourly_cost=4.032
                ;;
            r5.24xlarge)
                hourly_cost=6.048
                ;;
            *)
                # For unknown instance types, show a note instead of N/A
                hourly_cost="See AWS Pricing"
                ;;
        esac
        
        if [ "$hourly_cost" != "See AWS Pricing" ]; then
            monthly_cost=$(echo "$hourly_cost" | awk '{printf "%.2f", $1 * 24 * 30}')
        else
            monthly_cost="See AWS Pricing"
        fi
        
        # Check for Reserved Instances
        ri_status="On-Demand"
        ri_info=$(aws ec2 describe-reserved-instances \
            --region $REGION \
            $PROFILE \
            --query "ReservedInstances[?InstanceType=='$instance_type' && State=='active'].{Count:InstanceCount,Type:OfferingClass}" \
            --output text 2>/dev/null)
        
        if [ -n "$ri_info" ] && [ "$ri_info" != "None" ]; then
            ri_count=$(echo "$ri_info" | awk '{sum+=$1} END {print sum}')
            ri_type=$(echo "$ri_info" | awk '{print $2}' | head -1)
            if [ "$ri_count" -gt 0 ]; then
                ri_status="$ri_type RI"
                # Apply RI discount (approximate 30-60% savings)
                if [ "$monthly_cost" != "See AWS Pricing" ]; then
                    monthly_cost=$(echo "$monthly_cost" | awk '{printf "%.2f", $1 * 0.6}')
                fi
            fi
        fi
        
        printf "| %-*s | %-13s | %-5s | %-13s | %-14s | \$%-10s | %-11s |\n" $MAX_LENGTH "$instance_id" "$instance_type" "$state" "$az" "$launch_date" "$monthly_cost" "$ri_status"
    fi
done

# Close table
printf "+%*s+---------------+-------+---------------+----------------+-------------+-------------+\n" $MAX_LENGTH | tr ' ' '-'

echo ""
echo "Reserved Instances Summary:"
echo "=========================="
aws ec2 describe-reserved-instances \
    --region $REGION \
    $PROFILE \
    --query 'ReservedInstances[?State==`active`].[InstanceType,InstanceCount,OfferingClass,Duration,FixedPrice,UsagePrice]' \
    --output table 2>/dev/null || echo "No active Reserved Instances found"

echo ""
echo "Additional EC2 Components:"
echo "========================="

# EBS Volumes
echo "EBS Volumes:"
VOLUMES=$(aws ec2 describe-volumes --region $REGION $PROFILE --query 'Volumes[?State==`in-use`]' --output text 2>/dev/null | wc -l)
echo "- Attached volumes: $VOLUMES"
echo "- EBS costs are separate from EC2 compute costs"

# Elastic IPs
EIPS=$(aws ec2 describe-addresses --region $REGION $PROFILE --query 'Addresses[?AssociationId==null]' --output text 2>/dev/null | wc -l)
if [ "$EIPS" -gt 0 ]; then
    echo ""
    echo "Elastic IPs:"
    echo "- Unassociated Elastic IPs: $EIPS (charged \$0.005/hour each)"
fi

echo ""
echo "Cost Optimization Tips:"
echo "======================"
echo "• Use Reserved Instances for predictable workloads (up to 72% savings)"
echo "• Consider Spot Instances for fault-tolerant workloads (up to 90% savings)"
echo "• Right-size instances based on actual CPU and memory usage"
echo "• Use Auto Scaling to match capacity with demand"
echo "• Stop instances during non-business hours when possible"
echo "• Release unassociated Elastic IP addresses"
echo "• Use newer generation instance types for better price/performance"