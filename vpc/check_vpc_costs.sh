#!/bin/bash

# Script to check AWS VPC costs by region
# Usage: ./check_vpc_costs.sh [--profile profile_name] [region]

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

echo "VPC Cost Analysis - Region: $REGION (Last Month: $LAST_MONTH_START to $LAST_MONTH_END)"
echo "================================================================================"

# Get actual VPC-related costs from Cost Explorer
ACTUAL_COST=$(aws ce get-cost-and-usage \
    --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE \
    --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Virtual Private Cloud"]}}' \
    $PROFILE \
    --query 'ResultsByTime[*].Groups[?Keys[0]==`Amazon Virtual Private Cloud`].Metrics.BlendedCost.Amount' \
    --output text | awk '{print $1}')

echo "Actual Total VPC Cost from Cost Explorer: \$${ACTUAL_COST:-0.00}"
echo ""

# Get VPC cost breakdown by usage type
echo "VPC Cost Breakdown by Usage Type:"
echo "--------------------------------"

aws ce get-cost-and-usage \
    --time-period Start=$LAST_MONTH_START,End=$LAST_MONTH_END \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=USAGE_TYPE \
    --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Virtual Private Cloud"]}}' \
    $PROFILE \
    --query 'ResultsByTime[*].Groups[*].[Keys[0],Metrics.BlendedCost.Amount]' \
    --output text 2>/dev/null | \
    awk 'NF==2 && $2>0 {printf "%-50s $%.4f\n", $1, $2}' | \
    sort -k2 -nr

echo ""
echo "VPC Resources Analysis:"
echo "======================"

# NAT Gateways Analysis
echo ""
echo "NAT Gateways:"
echo "-------------"
printf "+-------------------------+------------------+-------+---------------+----------------+\n"
printf "| NAT Gateway ID          | Subnet           | State | AZ            | Est. Price     |\n"
printf "+-------------------------+------------------+-------+---------------+----------------+\n"

for nat_gw in $(aws ec2 describe-nat-gateways --region $REGION $PROFILE --query 'NatGateways[?State==`available`].NatGatewayId' --output text); do
    # Get NAT Gateway details
    nat_details=$(aws ec2 describe-nat-gateways --nat-gateway-ids $nat_gw --region $REGION $PROFILE \
        --query 'NatGateways[0].[SubnetId,State,AvailabilityZone]' --output text)
    
    subnet_id=$(echo $nat_details | awk '{print $1}')
    state=$(echo $nat_details | awk '{print $2}')
    az=$(echo $nat_details | awk '{print $3}')
    
    # If AZ is None, get it from subnet
    if [ "$az" = "None" ] || [ -z "$az" ]; then
        az=$(aws ec2 describe-subnets --subnet-ids $subnet_id --region $REGION $PROFILE \
            --query 'Subnets[0].AvailabilityZone' --output text 2>/dev/null)
    fi
    
    # Truncate subnet ID for better display
    subnet_short=$(echo $subnet_id | cut -c1-16)
    
    # Estimate cost: $0.045/hour * 720 hours = $32.40/month
    est_price="\$32.40/month"
    
    printf "| %-23s | %-16s | %-5s | %-13s | %-14s |\n" "$nat_gw" "$subnet_short" "$state" "$az" "$est_price"
done

printf "+-------------------------+------------------+-------+---------------+----------------+\n"

# VPC Endpoints Analysis
echo ""
echo "VPC Endpoints:"
echo "--------------"
printf "+-------------------------+------------------+----------+---------------+----------------+\n"
printf "| VPC Endpoint ID         | Service          | Type     | State         | Est. Price     |\n"
printf "+-------------------------+------------------+----------+---------------+----------------+\n"

for endpoint in $(aws ec2 describe-vpc-endpoints --region $REGION $PROFILE --query 'VpcEndpoints[?State==`available`].VpcEndpointId' --output text); do
    # Get VPC Endpoint details
    endpoint_details=$(aws ec2 describe-vpc-endpoints --vpc-endpoint-ids $endpoint --region $REGION $PROFILE \
        --query 'VpcEndpoints[0].[ServiceName,VpcEndpointType,State]' --output text)
    
    service_name=$(echo $endpoint_details | awk '{print $1}')
    endpoint_type=$(echo $endpoint_details | awk '{print $2}')
    state=$(echo $endpoint_details | awk '{print $3}')
    
    # Extract service name (remove region prefix and vpce-svc prefix)
    if [[ "$service_name" == *"."* ]]; then
        service_short=$(echo $service_name | sed 's/.*\.//' | cut -c1-16)
    elif [[ "$service_name" == "vpce-svc-"* ]]; then
        service_short="custom-svc"
    else
        service_short=$(echo $service_name | cut -c1-16)
    fi
    
    # Estimate cost based on type
    if [[ "$endpoint_type" == "Interface" ]]; then
        est_price="\$7.20/month"  # $0.01/hour * 720 hours
    else
        est_price="\$0.00/month"  # Gateway endpoints are free
    fi
    
    printf "| %-23s | %-16s | %-8s | %-13s | %-14s |\n" "$endpoint" "$service_short" "$endpoint_type" "$state" "$est_price"
done

printf "+-------------------------+------------------+----------+---------------+----------------+\n"

# VPC Peering Connections
echo ""
echo "VPC Peering Connections:"
echo "------------------------"
printf "+-------------------------+---------------+------------------+------------------+\n"
printf "| Peering Connection ID   | Status        | Accepter VPC     | Requester VPC    |\n"
printf "+-------------------------+---------------+------------------+------------------+\n"

for peering in $(aws ec2 describe-vpc-peering-connections --region $REGION $PROFILE --query 'VpcPeeringConnections[?Status.Code==`active`].VpcPeeringConnectionId' --output text); do
    # Get peering connection details
    peering_details=$(aws ec2 describe-vpc-peering-connections --vpc-peering-connection-ids $peering --region $REGION $PROFILE \
        --query 'VpcPeeringConnections[0].[Status.Code,AccepterVpcInfo.VpcId,RequesterVpcInfo.VpcId]' --output text)
    
    status=$(echo $peering_details | awk '{print $1}')
    accepter_vpc=$(echo $peering_details | awk '{print $2}' | cut -c1-16)
    requester_vpc=$(echo $peering_details | awk '{print $3}' | cut -c1-16)
    
    printf "| %-23s | %-13s | %-16s | %-16s |\n" "$peering" "$status" "$accepter_vpc" "$requester_vpc"
done

printf "+-------------------------+---------------+------------------+------------------+\n"

# Internet Gateways
echo ""
echo "Internet Gateways:"
echo "------------------"
printf "+-------------------------+---------------+------------------+\n"
printf "| Internet Gateway ID     | State         | VPC              |\n"
printf "+-------------------------+---------------+------------------+\n"

for igw in $(aws ec2 describe-internet-gateways --region $REGION $PROFILE --query 'InternetGateways[].InternetGatewayId' --output text); do
    # Get IGW details
    igw_details=$(aws ec2 describe-internet-gateways --internet-gateway-ids $igw --region $REGION $PROFILE \
        --query 'InternetGateways[0].[Attachments[0].State,Attachments[0].VpcId]' --output text)
    
    state=$(echo $igw_details | awk '{print $1}')
    vpc_id=$(echo $igw_details | awk '{print $2}' | cut -c1-16)
    
    if [ "$state" = "None" ]; then
        state="detached"
        vpc_id="N/A"
    fi
    
    printf "| %-23s | %-13s | %-16s |\n" "$igw" "$state" "$vpc_id"
done

printf "+-------------------------+---------------+------------------+\n"

# Elastic IPs
echo ""
echo "Elastic IP Addresses:"
echo "---------------------"
printf "+-------------------------+---------------+-------+------------------+\n"
printf "| Allocation ID           | Public IP     | State | Instance/NAT     |\n"
printf "+-------------------------+---------------+-------+------------------+\n"

aws ec2 describe-addresses --region $REGION $PROFILE \
    --query 'Addresses[*].[AllocationId,PublicIp,Domain,InstanceId,NetworkInterfaceId]' \
    --output text | \
    while read alloc_id public_ip domain instance_id eni_id; do
        if [ "$instance_id" != "None" ]; then
            associated_with=$(echo $instance_id | cut -c1-16)
            state="in-use"
        elif [ "$eni_id" != "None" ]; then
            associated_with=$(echo $eni_id | cut -c1-16)
            state="in-use"
        else
            associated_with="unassociated"
            state="available"
        fi
        
        printf "| %-23s | %-13s | %-5s | %-16s |\n" "$alloc_id" "$public_ip" "$state" "$associated_with"
    done

printf "+-------------------------+---------------+-------+------------------+\n"

echo ""
echo "VPC Pricing Guide (us-east-1):"
echo "=============================="
echo "NAT Gateway:"
echo "  Hourly charge: \$0.045 per hour"
echo "  Data processing: \$0.045 per GB"
echo "  Monthly estimate: ~\$32.40 (720 hours)"
echo ""
echo "VPC Endpoints:"
echo "  Interface endpoints: \$0.01 per hour per endpoint"
echo "  Gateway endpoints: Free"
echo "  Data processing: \$0.01 per GB"
echo ""
echo "Elastic IP Addresses:"
echo "  Associated: Free"
echo "  Unassociated: \$0.005 per hour (\$3.60/month)"
echo ""
echo "VPC Peering:"
echo "  Same AZ: Free"
echo "  Cross AZ: \$0.01 per GB"
echo "  Cross Region: \$0.02 per GB"
echo ""
echo "Cost Optimization Tips:"
echo "======================="
echo "1. Remove unused Elastic IP addresses"
echo "2. Use Gateway endpoints instead of Interface endpoints when possible"
echo "3. Consolidate NAT Gateways across multiple subnets if traffic is low"
echo "4. Monitor data transfer costs through NAT Gateways"
echo "5. Consider VPC endpoints for AWS services to reduce NAT Gateway usage"
echo "6. Review VPC peering connections for unused connections"