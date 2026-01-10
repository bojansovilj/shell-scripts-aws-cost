#!/bin/bash

# Script to check AWS Glue job costs by region
# Usage: ./check_glue_costs.sh [--profile profile_name] [region]

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

# Get actual Glue costs from Cost Explorer
ACTUAL_COST=$(aws ce get-cost-and-usage \
    --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE \
    --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Glue"]}}' \
    $PROFILE \
    --query 'ResultsByTime[*].Groups[?Keys[0]==`Amazon Glue`].Metrics.BlendedCost.Amount' \
    --output text | awk '{print $1}')

echo "Glue Job Analysis - Region: $REGION (Last Month: $LAST_MONTH_START to $LAST_MONTH_END)"
echo "Actual Total Cost from Cost Explorer: \$$ACTUAL_COST"
echo ""

# Find longest job name to set column width
MAX_LENGTH=$(aws glue get-jobs --region $REGION $PROFILE --query 'Jobs[*].Name' --output text | tr '\t' '\n' | awk '{if(length > max) max = length} END {print max+5}')

# Create table header
printf "+%*s+----------+-------+---------------+----------------+-------------+\n" $MAX_LENGTH | tr ' ' '-'
printf "| %-*s | Capacity | Runs  | Last Duration | Total Duration | Est. Price  |\n" $MAX_LENGTH "Job Name"
printf "+%*s+----------+-------+---------------+----------------+-------------+\n" $MAX_LENGTH | tr ' ' '-'

# Get job details with estimated price calculation
for job in $(aws glue get-jobs --region $REGION $PROFILE --query 'Jobs[*].Name' --output text); do
    # Get job capacity
    capacity=$(aws glue get-job --job-name "$job" --region $REGION $PROFILE --query 'Job.MaxCapacity' --output text 2>/dev/null)
    
    # Get job runs from last month only
    job_runs=$(aws glue get-job-runs --job-name "$job" --region $REGION $PROFILE \
        --query "JobRuns[?StartedOn>=\`${LAST_MONTH_START}\` && StartedOn<=\`${LAST_MONTH_END}\`].ExecutionTime" \
        --output text 2>/dev/null)
    
    if [ -n "$job_runs" ] && [ "$job_runs" != "None" ] && [ "$job_runs" != "" ]; then
        # Count number of runs
        num_runs=$(echo $job_runs | wc -w | xargs)
        
        # Calculate last duration and total duration for last month
        last_duration=$(echo $job_runs | awk '{print $1}')
        total_duration=$(echo $job_runs | awk '{sum=0; for(i=1;i<=NF;i++) sum+=$i; print sum}')
        
        # Estimate price based on DPU-hours (more conservative rate)
        total_hours=$(echo "$total_duration" | awk '{print $1/3600}')
        est_price=$(echo "$capacity $total_hours" | awk '{printf "%.2f", $1 * $2 * 0.30}')
        
        printf "| %-*s | %-8s | %-5s | %-13s | %-14s | \$%-10s |\n" $MAX_LENGTH "$job" "$capacity" "$num_runs" "${last_duration}s" "${total_duration}s" "$est_price"
    else
        printf "| %-*s | %-8s | %-5s | %-13s | %-14s | \$%-10s |\n" $MAX_LENGTH "$job" "$capacity" "0" "No runs" "0s" "0.00"
    fi
done

# Close table
printf "+%*s+----------+-------+---------------+----------------+-------------+\n" $MAX_LENGTH | tr ' ' '-'