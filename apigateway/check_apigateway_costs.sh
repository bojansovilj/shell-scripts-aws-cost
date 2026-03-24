#!/bin/bash

# Script to check AWS API Gateway costs by region
# Usage: ./check_apigateway_costs.sh [--profile profile_name] [region]

PROFILE=""
REGION=""

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

if [ -z "$REGION" ]; then
    REGION=$(aws configure get region $PROFILE)
fi

LAST_MONTH_START=$(date -v-1m -v1d '+%Y-%m-%d')
LAST_MONTH_END=$(date -v1d '+%Y-%m-%d')

echo "API Gateway Cost Analysis - Region: $REGION (Last Month: $LAST_MONTH_START to $LAST_MONTH_END)"
echo "=========================================================================================="

# Actual costs from Cost Explorer
ACTUAL_COST=$(aws ce get-cost-and-usage \
    --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon API Gateway"]}}' \
    $PROFILE \
    --query 'ResultsByTime[0].Total.BlendedCost.Amount' \
    --output text 2>/dev/null)

echo "Actual Total Cost from Cost Explorer: \$${ACTUAL_COST:-0.00}"
echo ""

# Cost breakdown by usage type
echo "API Gateway Cost Breakdown by Usage Type:"
echo "-----------------------------------------"
aws ce get-cost-and-usage \
    --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=USAGE_TYPE \
    --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon API Gateway"]}}' \
    $PROFILE \
    --query 'ResultsByTime[0].Groups[*].[Keys[0],Metrics.BlendedCost.Amount]' \
    --output text 2>/dev/null | \
    awk '$2>0 {printf "%-50s $%.4f\n", $1, $2}' | sort -k2 -nr

echo ""

# REST APIs (v1)
echo "REST APIs (v1):"
echo "==============="

REST_APIS=$(aws apigateway get-rest-apis --region $REGION $PROFILE \
    --query 'items[*].[id,name,createdDate]' --output text 2>/dev/null)

if [ -z "$REST_APIS" ]; then
    echo "No REST APIs found."
else
    MAX_NAME=$(echo "$REST_APIS" | awk '{if(length($2) > max) max = length($2)} END {print (max<20?20:max)+2}')

    printf "+%*s+------------+------------------+------------------+------------------+\n" $MAX_NAME | tr ' ' '-'
    printf "| %-*s | Stages     | Calls (last mo.) | Latency avg (ms) | Est. Price       |\n" $MAX_NAME "API Name"
    printf "+%*s+------------+------------------+------------------+------------------+\n" $MAX_NAME | tr ' ' '-'

    echo "$REST_APIS" | while read -r api_id api_name created; do
        # Count stages
        stages=$(aws apigateway get-stages --rest-api-id "$api_id" --region $REGION $PROFILE \
            --query 'length(item)' --output text 2>/dev/null)

        # CloudWatch metrics for call count
        calls=$(aws cloudwatch get-metric-statistics \
            --namespace AWS/ApiGateway \
            --metric-name Count \
            --dimensions Name=ApiName,Value="$api_name" \
            --start-time "${LAST_MONTH_START}T00:00:00Z" \
            --end-time "${LAST_MONTH_END}T00:00:00Z" \
            --period 2592000 \
            --statistics Sum \
            --region $REGION $PROFILE \
            --query 'Datapoints[0].Sum' --output text 2>/dev/null)

        # Average latency
        latency=$(aws cloudwatch get-metric-statistics \
            --namespace AWS/ApiGateway \
            --metric-name Latency \
            --dimensions Name=ApiName,Value="$api_name" \
            --start-time "${LAST_MONTH_START}T00:00:00Z" \
            --end-time "${LAST_MONTH_END}T00:00:00Z" \
            --period 2592000 \
            --statistics Average \
            --region $REGION $PROFILE \
            --query 'Datapoints[0].Average' --output text 2>/dev/null)

        calls_clean=$(echo "${calls:-0}" | awk '{printf "%.0f", $1+0}')
        latency_clean=$(echo "${latency:-0}" | awk '{printf "%.1f", $1+0}')

        # REST API pricing: $3.50 per million calls (first 333M)
        est_price=$(echo "$calls_clean" | awk '{printf "%.4f", ($1/1000000) * 3.50}')

        printf "| %-*s | %-10s | %-16s | %-16s | \$%-15s |\n" \
            $MAX_NAME "$api_name" "${stages:-0}" "$calls_clean" "$latency_clean" "$est_price"
    done

    printf "+%*s+------------+------------------+------------------+------------------+\n" $MAX_NAME | tr ' ' '-'
fi

echo ""

# HTTP APIs (v2)
echo "HTTP APIs (v2):"
echo "==============="

HTTP_APIS=$(aws apigatewayv2 get-apis --region $REGION $PROFILE \
    --query 'Items[?ProtocolType==`HTTP`].[ApiId,Name,CreatedDate]' --output text 2>/dev/null)

if [ -z "$HTTP_APIS" ]; then
    echo "No HTTP APIs found."
else
    MAX_NAME_V2=$(echo "$HTTP_APIS" | awk '{if(length($2) > max) max = length($2)} END {print (max<20?20:max)+2}')

    printf "+%*s+------------------+------------------+------------------+\n" $MAX_NAME_V2 | tr ' ' '-'
    printf "| %-*s | Calls (last mo.) | Latency avg (ms) | Est. Price       |\n" $MAX_NAME_V2 "API Name"
    printf "+%*s+------------------+------------------+------------------+\n" $MAX_NAME_V2 | tr ' ' '-'

    echo "$HTTP_APIS" | while read -r api_id api_name created; do
        calls=$(aws cloudwatch get-metric-statistics \
            --namespace AWS/ApiGateway \
            --metric-name Count \
            --dimensions Name=ApiId,Value="$api_id" \
            --start-time "${LAST_MONTH_START}T00:00:00Z" \
            --end-time "${LAST_MONTH_END}T00:00:00Z" \
            --period 2592000 \
            --statistics Sum \
            --region $REGION $PROFILE \
            --query 'Datapoints[0].Sum' --output text 2>/dev/null)

        latency=$(aws cloudwatch get-metric-statistics \
            --namespace AWS/ApiGateway \
            --metric-name Latency \
            --dimensions Name=ApiId,Value="$api_id" \
            --start-time "${LAST_MONTH_START}T00:00:00Z" \
            --end-time "${LAST_MONTH_END}T00:00:00Z" \
            --period 2592000 \
            --statistics Average \
            --region $REGION $PROFILE \
            --query 'Datapoints[0].Average' --output text 2>/dev/null)

        calls_clean=$(echo "${calls:-0}" | awk '{printf "%.0f", $1+0}')
        latency_clean=$(echo "${latency:-0}" | awk '{printf "%.1f", $1+0}')

        # HTTP API pricing: $1.00 per million calls (first 300M)
        est_price=$(echo "$calls_clean" | awk '{printf "%.4f", ($1/1000000) * 1.00}')

        printf "| %-*s | %-16s | %-16s | \$%-15s |\n" \
            $MAX_NAME_V2 "$api_name" "$calls_clean" "$latency_clean" "$est_price"
    done

    printf "+%*s+------------------+------------------+------------------+\n" $MAX_NAME_V2 | tr ' ' '-'
fi

echo ""

# WebSocket APIs
echo "WebSocket APIs:"
echo "==============="

WS_APIS=$(aws apigatewayv2 get-apis --region $REGION $PROFILE \
    --query 'Items[?ProtocolType==`WEBSOCKET`].[ApiId,Name]' --output text 2>/dev/null)

if [ -z "$WS_APIS" ]; then
    echo "No WebSocket APIs found."
else
    MAX_NAME_WS=$(echo "$WS_APIS" | awk '{if(length($2) > max) max = length($2)} END {print (max<20?20:max)+2}')

    printf "+%*s+---------------------+---------------------+\n" $MAX_NAME_WS | tr ' ' '-'
    printf "| %-*s | Connection Minutes  | Messages            |\n" $MAX_NAME_WS "API Name"
    printf "+%*s+---------------------+---------------------+\n" $MAX_NAME_WS | tr ' ' '-'

    echo "$WS_APIS" | while read -r api_id api_name; do
        conn_mins=$(aws cloudwatch get-metric-statistics \
            --namespace AWS/ApiGateway \
            --metric-name ConnectCount \
            --dimensions Name=ApiId,Value="$api_id" \
            --start-time "${LAST_MONTH_START}T00:00:00Z" \
            --end-time "${LAST_MONTH_END}T00:00:00Z" \
            --period 2592000 \
            --statistics Sum \
            --region $REGION $PROFILE \
            --query 'Datapoints[0].Sum' --output text 2>/dev/null)

        messages=$(aws cloudwatch get-metric-statistics \
            --namespace AWS/ApiGateway \
            --metric-name MessageCount \
            --dimensions Name=ApiId,Value="$api_id" \
            --start-time "${LAST_MONTH_START}T00:00:00Z" \
            --end-time "${LAST_MONTH_END}T00:00:00Z" \
            --period 2592000 \
            --statistics Sum \
            --region $REGION $PROFILE \
            --query 'Datapoints[0].Sum' --output text 2>/dev/null)

        printf "| %-*s | %-19s | %-19s |\n" \
            $MAX_NAME_WS "$api_name" "${conn_mins:-0}" "${messages:-0}"
    done

    printf "+%*s+---------------------+---------------------+\n" $MAX_NAME_WS | tr ' ' '-'
fi

echo ""
echo "Pricing Reference:"
echo "------------------"
echo "REST API (v1): \$3.50 per million API calls"
echo "HTTP API (v2): \$1.00 per million API calls (first 300M/month)"
echo "WebSocket:     \$0.80 per million messages + \$0.25 per million connection minutes"
echo "Cache:         \$0.02-\$3.84/hour depending on cache size"
