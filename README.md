# AWS Cost Analysis Shell Scripts

A collection of bash scripts to analyze AWS service costs and usage metrics using AWS CLI. These scripts provide detailed cost breakdowns, usage statistics, and optimization recommendations for various AWS services.

## Prerequisites

### 1. Install AWS CLI
```bash
# macOS
brew install awscli

# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Verify installation
aws --version
```

### 2. Configure AWS Credentials
```bash
# Configure default profile
aws configure

# Or configure named profile
aws configure --profile my-profile
```

### 3. Required AWS Permissions
Ensure your AWS user/role has the following permissions:
- `ce:GetCostAndUsage` (Cost Explorer)
- `cloudwatch:GetMetricStatistics`
- Service-specific read permissions (e.g., `lambda:ListFunctions`, `s3:ListBuckets`, `redshift:DescribeClusters`, `redshift:DescribeReservedNodes`, `ec2:DescribeInstances`, `ec2:DescribeReservedInstances`, `dynamodb:ListTables`, `dynamodb:DescribeTable`)

### 4. Make Scripts Executable
```bash
# Clone the repository
git clone <repository-url>
cd shell-scripts-aws-cost

# Make all scripts executable
chmod +x */*.sh

# Or make individual scripts executable
chmod +x lambda/check_lambda_costs.sh
chmod +x s3/check_s3_costs.sh
chmod +x redshift/check_redshift_costs.sh
chmod +x ec2/check_ec2_costs.sh
chmod +x dynamodb/check_dynamodb_costs.sh
# ... etc
```

## Available Scripts

| Script | Purpose | Key Metrics |
|--------|---------|-------------|
| `sqs/check_sqs_metrics.sh` | SQS queue analysis | Messages sent, queue depth |
| `lambda/check_lambda_costs.sh` | Lambda function costs | Invocations, duration, memory usage |
| `glue/check_glue_costs.sh` | Glue job costs | Job runs, execution time, DPU usage |
| `s3/check_s3_costs.sh` | S3 storage costs | Bucket sizes, storage classes |
| `cloudwatch/check_cloudwatch_costs.sh` | CloudWatch costs | Alarms, dashboards, log groups |
| `natgateway/check_natgateway_costs.sh` | NAT Gateway costs | Data transfer, hourly charges |
| `datatransfer/check_datatransfer_costs.sh` | Data transfer costs | Cross-region, internet transfers |
| `redshift/check_redshift_costs.sh` | Redshift cluster costs | Node types, cluster status, backup storage, Reserved Instances |
| `ec2/check_ec2_costs.sh` | EC2 instance costs | Instance types, states, Reserved Instances, EBS volumes |
| `dynamodb/check_dynamodb_costs.sh` | DynamoDB table costs | Billing modes, capacity units, item counts |

## Usage

All scripts follow the same usage pattern:

```bash
# Basic usage (uses default AWS profile and region)
./service/check_service_costs.sh

# Specify region
./service/check_service_costs.sh us-west-2

# Use specific AWS profile
./service/check_service_costs.sh --profile my-profile

# Use specific profile and region
./service/check_service_costs.sh --profile my-profile us-east-1
```

## Detailed Usage Examples

### 1. Lambda Cost Analysis

```bash
# Run Lambda cost analysis
./lambda/check_lambda_costs.sh --profile production us-east-1
```

**Sample Output:**
```
Lambda Function Analysis - Region: us-east-1 (Last Month: 2024-01-01 to 2024-02-01)
Actual Total Cost from Cost Explorer: $45.67

+----------------------------------+----------+-------+---------------+----------------+-------------+
| Function Name                    | Memory   | Runs  | Avg Duration  | Total Duration | Est. Price  |
+----------------------------------+----------+-------+---------------+----------------+-------------+
| data-processor                   | 512MB    | 1250  | 2340ms        | 2925000ms      | $24.35      |
| api-handler                      | 256MB    | 8900  | 150ms         | 1335000ms      | $12.89      |
| scheduled-backup                 | 1024MB   | 30    | 45000ms       | 1350000ms      | $8.43       |
+----------------------------------+----------+-------+---------------+----------------+-------------+
```

**What it shows:**
- Actual costs from AWS Cost Explorer
- Function memory allocation
- Number of invocations
- Average and total execution duration
- Estimated cost breakdown per function

### 2. S3 Storage Analysis

```bash
# Analyze S3 costs
./s3/check_s3_costs.sh --profile production
```

**Sample Output:**
```
S3 Cost Analysis - Region: us-east-1 (Last Month: 2024-01-01 to 2024-02-01)
Actual Total S3 Cost from Cost Explorer: $127.45

S3 Cost Breakdown by Usage Type:
--------------------------------
USE1-TimedStorage-Standard                       $89.2340
USE1-Requests-Tier1                              $12.4500
USE1-DataTransfer-Out-Bytes                      $25.7660

S3 Buckets Analysis:
====================
+----------------------------------------+---------------+---------------+------------------+
| Bucket Name                            | Size (GB)     | Objects       | Est. Monthly Cost |
+----------------------------------------+---------------+---------------+------------------+
| company-data-lake                      | 3847.23       | 125000        | $88.49           |
| application-logs                       | 892.45        | 45000         | $20.53           |
| backup-storage                         | 234.67        | 8900          | $5.40            |
+----------------------------------------+---------------+---------------+------------------+
```

**What it shows:**
- Total S3 costs from Cost Explorer
- Cost breakdown by usage type (storage, requests, data transfer)
- Individual bucket analysis with size and estimated costs
- Storage optimization recommendations

### 3. Glue Job Analysis

```bash
# Check Glue job costs
./glue/check_glue_costs.sh us-west-2
```

**Sample Output:**
```
Glue Job Analysis - Region: us-west-2 (Last Month: 2024-01-01 to 2024-02-01)
Actual Total Cost from Cost Explorer: $234.56

+----------------------------------+----------+-------+---------------+----------------+-------------+
| Job Name                         | Capacity | Runs  | Last Duration | Total Duration | Est. Price  |
+----------------------------------+----------+-------+---------------+----------------+-------------+
| etl-daily-processing             | 10       | 31    | 3600s         | 111600s        | $93.00      |
| data-transformation              | 5        | 15    | 2400s         | 36000s         | $45.00      |
| weekly-aggregation               | 20       | 4     | 7200s         | 28800s         | $96.00      |
+----------------------------------+----------+-------+---------------+----------------+-------------+
```

**What it shows:**
- Glue job capacity (DPU allocation)
- Number of job runs in the last month
- Execution duration statistics
- Cost estimates based on DPU-hours

### 4. CloudWatch Cost Analysis

```bash
# Analyze CloudWatch costs
./cloudwatch/check_cloudwatch_costs.sh --profile monitoring
```

**Sample Output:**
```
CloudWatch Cost Analysis - Region: us-east-1 (Last Month: 2024-01-01 to 2024-02-01)
Actual Total Cost from Cost Explorer: $67.89

Quick Usage Summary:
-------------------
Alarms (first 100): 45
Dashboards: 8
Log Groups (first 50): 23

Cost Breakdown by Usage Type:
-----------------------------
USE1-DataProcessing-Bytes                        $34.5600
USE1-TimedStorage-ByteHrs                        $18.9900
USE1-Requests                                     $14.3400

Estimated Costs Based on Usage:
-------------------------------
Alarms: $4.50 (45 × $0.10)
Dashboards: $24.00 (8 × $3.00)
Log Groups: Variable cost based on ingestion and storage

Log Groups by Data Volume (Top 20):
====================================
+--------------------------------------------------+------------+------------------+
| Log Group Name                                   | Size (MB)  | Est. Monthly Cost |
+--------------------------------------------------+------------+------------------+
| /aws/lambda/api-handler                          |    2847.23 | $1.47            |
| /aws/apigateway/access-logs                      |    1234.56 | $0.64            |
| /aws/ecs/application                             |     892.34 | $0.46            |
+--------------------------------------------------+------------+------------------+
```

**What it shows:**
- CloudWatch alarms, dashboards, and log groups count
- Cost breakdown by usage type
- Estimated costs for alarms and dashboards
- Log groups sorted by data volume with cost estimates

### 5. Redshift Cost Analysis

```bash
# Check Redshift cluster costs
./redshift/check_redshift_costs.sh --profile production us-east-1
```

**Sample Output:**
```
Redshift Cluster Analysis - Region: us-east-1 (Last Month: 2024-01-01 to 2024-02-01)
Actual Total Cost from Cost Explorer: $1,234.56

Redshift Cost Breakdown by Usage Type:
-------------------------------------
USE1-Node-ra3.xlplus                            $789.2340
USE1-ManagedStorage-ByteHrs                     $234.5600
USE1-DataTransfer-Out-Bytes                     $210.7660

Redshift Clusters Analysis:
==========================
+----------------------------------+---------------+-------+---------------+----------------+-------------+-------------+
| Cluster Identifier               | Node Type     | Nodes | Status        | Created        | Est. Price  | RI Status   |
+----------------------------------+---------------+-------+---------------+----------------+-------------+-------------+
| production-cluster               | ra3.xlplus    | 3     | available     | 2024-01-15     | $1,175.00   | 1-year RI   |
| analytics-cluster                | ra3.4xlarge   | 2     | available     | 2024-02-01     | $4,708.80   | On-Demand   |
+----------------------------------+---------------+-------+---------------+----------------+-------------+-------------+

Reserved Instances Summary:
==========================
|    NodeType    | NodeCount | OfferingType |  Duration  | FixedPrice | UsagePrice |
|----------------|-----------|--------------|------------|------------|------------|
|  ra3.xlplus    |     3     |   All Upfront|   31536000 |   9500.00  |    0.00    |
```

**What it shows:**
- Actual costs from AWS Cost Explorer
- Cost breakdown by usage type (compute, storage, data transfer)
- Cluster details with node types and Reserved Instance status
- Estimated costs with RI discounts applied when detected
- Active Reserved Instances summary with pricing details
- Backup storage and Spectrum usage information

### 6. EC2 Cost Analysis

```bash
# Check EC2 instance costs
./ec2/check_ec2_costs.sh --profile production us-east-1
```

**Sample Output:**
```
EC2 Instance Analysis - Region: us-east-1 (Last Month: 2024-01-01 to 2024-02-01)
Actual Total Cost from Cost Explorer: $456.78

EC2 Cost Breakdown by Usage Type:
---------------------------------
USE1-BoxUsage:t3.medium                         $89.2340
USE1-BoxUsage:m5.large                          $234.5600
USE1-EBS:VolumeUsage.gp2                        $45.7800

EC2 Instances Analysis:
======================
+-------------------------+---------------+-------+---------------+----------------+-------------+-------------+
| Instance ID             | Instance Type | State | AZ            | Launch Time    | Est. Price  | RI Status   |
+-------------------------+---------------+-------+---------------+----------------+-------------+-------------+
| i-1234567890abcdef0     | t3.medium     | running| us-east-1a   | 2024-01-15     | $29.95      | On-Demand   |
| i-0987654321fedcba0     | m5.large      | running| us-east-1b   | 2024-01-10     | $69.12      | Standard RI |
+-------------------------+---------------+-------+---------------+----------------+-------------+-------------+
```

**What it shows:**
- Actual EC2 costs from Cost Explorer
- Cost breakdown by usage type (instance hours, EBS storage)
- Instance details with types, states, and Reserved Instance status
- **Estimated prices assume 24/7 On-Demand usage for full month (720 hours)**
- RI discounts applied when Reserved Instances are detected
- Additional components like EBS volumes and Elastic IPs

**Important Note:** The estimated prices shown are calculated assuming instances run 24/7 for a full month. If your instances run only several hours daily or are stopped/started frequently, your actual costs will be significantly lower than the estimates shown.

### 7. DynamoDB Cost Analysis

```bash
# Check DynamoDB table costs
./dynamodb/check_dynamodb_costs.sh --profile production us-east-1
```

**Sample Output:**
```
DynamoDB Analysis - Region: us-east-1 (Last Month: 2024-01-01 to 2024-02-01)
Actual Total Cost from Cost Explorer: $89.34

DynamoDB Cost Breakdown by Usage Type:
-------------------------------------
USE1-TimedStorage-ByteHrs                       $34.5600
USE1-WriteRequestUnits                           $28.9900
USE1-ReadRequestUnits                            $25.7800

DynamoDB Tables Analysis:
========================
+----------------------------------+---------------+-------+---------------+----------------+-------------+
| Table Name                       | Billing Mode  | Status| Read/Write    | Item Count     | Est. Price  |
+----------------------------------+---------------+-------+---------------+----------------+-------------+
| user-sessions                    | PAY_PER_REQUEST| ACTIVE| On-Demand     | 2.5M           | $3.12       |
| product-catalog                  | PROVISIONED   | ACTIVE| 100R/50W      | 450.0K         | $56.16      |
| analytics-events                 | PAY_PER_REQUEST| ACTIVE| On-Demand     | 12.8M          | $16.00      |
+----------------------------------+---------------+-------+---------------+----------------+-------------+
```

**What it shows:**
- Actual DynamoDB costs from Cost Explorer
- Cost breakdown by usage type (storage, read/write requests)
- Table details with billing modes and capacity settings
- Estimated costs for both Provisioned and On-Demand tables
- Item counts and table status information
- Global Tables and backup information

### 8. NAT Gateway Cost Analysis

```bash
# Check NAT Gateway costs
./natgateway/check_natgateway_costs.sh --profile production us-east-1
```

**Sample Output:**
```
NAT Gateway Cost Analysis - Region: us-east-1 (Last Month: 2024-01-01 to 2024-02-01)
Actual Total Cost from Cost Explorer: $67.89

NAT Gateway Cost Breakdown:
--------------------------
Hourly charges: $45.00 (1 gateway × $0.045/hour × 720 hours)
Data processing: $22.89 (458.2 GB processed × $0.045/GB)

NAT Gateways Analysis:
=====================
+-------------------------+---------------+-------+---------------+----------------+
| NAT Gateway ID          | Subnet        | State | AZ            | Est. Price     |
+-------------------------+---------------+-------+---------------+----------------+
| nat-1234567890abcdef0   | subnet-abc123 | available | us-east-1a | $45.00/month   |
+-------------------------+---------------+-------+---------------+----------------+
```

**What it shows:**
- Actual NAT Gateway costs from Cost Explorer
- Breakdown of hourly charges vs data processing costs
- NAT Gateway details with availability zones
- Data transfer volume and associated costs

### 9. Data Transfer Cost Analysis

```bash
# Check data transfer costs
./datatransfer/check_datatransfer_costs.sh --profile production
```

**Sample Output:**
```
Data Transfer Cost Analysis (Last Month: 2024-01-01 to 2024-02-01)
Actual Total Cost from Cost Explorer: $234.56

Data Transfer Cost Breakdown:
----------------------------
DataTransfer-Out-Bytes                          $156.7800
DataTransfer-Regional-Bytes                     $45.2300
DataTransfer-In-Bytes                           $0.0000
CloudFront-Out-Bytes                            $32.5500

Top Data Transfer Sources:
=========================
- Internet egress: 1.2 TB ($156.78)
- Cross-region transfers: 905 GB ($45.23)
- CloudFront distribution: 2.1 TB ($32.55)
```

**What it shows:**
- Total data transfer costs across all services
- Breakdown by transfer type (internet, regional, CloudFront)
- Volume of data transferred and associated costs
- Identification of major data transfer sources

### 10. SQS Metrics Analysis

```bash
# Check SQS queue metrics
./sqs/check_sqs_metrics.sh --profile production us-east-1
```

**Sample Output:**
```
SQS Queue Analysis - Region: us-east-1 (Last Month: 2024-01-01 to 2024-02-01)

SQS Queues Analysis:
===================
+----------------------------------+----------+-------+---------------+----------------+
| Queue Name                       | Messages | Depth | Avg Depth     | Est. Requests  |
+----------------------------------+----------+-------+---------------+----------------+
| order-processing-queue           | 125000   | 45    | 23.5          | 2.5M           |
| notification-queue               | 89000    | 12    | 8.2           | 1.8M           |
| dead-letter-queue                | 234      | 0     | 0.1           | 468            |
+----------------------------------+----------+-------+---------------+----------------+

Cost Estimation:
===============
Total estimated requests: 4.3M
Estimated monthly cost: $1.72 (4.3M requests × $0.40 per million)
```

**What it shows:**
- Queue message volumes and depths
- Average queue depth over time
- Estimated request counts and associated costs
- Queue performance metrics

## Cost Optimization Tips

### Lambda
- Right-size memory allocation based on actual usage
- Optimize function duration to reduce compute costs
- Use provisioned concurrency only when necessary

### S3
- Implement lifecycle policies to move data to cheaper storage classes
- Use S3 Intelligent Tiering for automatic optimization
- Delete incomplete multipart uploads
- Enable S3 Storage Class Analysis

### Glue
- Optimize job capacity based on actual requirements
- Use job bookmarks to avoid reprocessing data
- Consider using Glue Flex for variable workloads

### CloudWatch
- Review and remove unused alarms
- Optimize log retention periods
- Use log filtering to reduce ingestion costs

### DynamoDB
- Use On-Demand billing for unpredictable workloads
- Use Provisioned billing with Auto Scaling for predictable workloads
- Implement efficient query patterns to reduce RCU/WCU consumption
- Use Global Secondary Indexes (GSI) sparingly and optimize projections
- Consider DynamoDB Standard-IA for infrequently accessed data

### EC2
- Use Reserved Instances for predictable workloads (up to 72% savings)
- Consider Spot Instances for fault-tolerant workloads (up to 90% savings)
- Right-size instances based on actual CPU and memory usage
- Stop instances during non-business hours when possible
- Release unassociated Elastic IP addresses

### Redshift
- Use Reserved Instances for predictable workloads (up to 75% savings)
- Consider pausing clusters during non-business hours
- Use RA3 nodes with managed storage for better cost efficiency
- Monitor and optimize query performance to reduce compute time
- Use Redshift Spectrum for infrequently accessed data

## Troubleshooting

### Common Issues

1. **Permission Denied**
   ```bash
   chmod +x script_name.sh
   ```

2. **AWS CLI Not Found**
   ```bash
   # Install AWS CLI (see Prerequisites)
   aws --version
   ```

3. **No Cost Data**
   - Ensure Cost Explorer is enabled in your AWS account
   - Check if you have `ce:GetCostAndUsage` permission
   - Verify the time period has actual usage

4. **Region Not Found**
   ```bash
   # List available regions
   aws ec2 describe-regions --query 'Regions[].RegionName' --output text
   ```

### Debug Mode

Run scripts with debug output:
```bash
bash -x ./lambda/check_lambda_costs.sh
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add your improvements
4. Test thoroughly
5. Submit a pull request

## License

MIT License - see LICENSE file for details
