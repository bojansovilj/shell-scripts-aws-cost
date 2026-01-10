# shell-scripts-aws-cost

This repo contains shell scripts that are using AWS cli call to access costs for various AWS services:

/sqs/check_sqs_metrics.sh - this is for number of messages sent to sqs
/glue/check_glue_costs.sh - this checks AWS Glue job costs and identifies most expensive jobs
/lambda/check_lambda_costs.sh - this checks AWS Lambda function costs and execution metrics
/cloudwatch/check_cloudwatch_costs.sh - this checks AWS CloudWatch costs and usage breakdown
/natgateway/check_natgateway_costs.sh - this checks AWS NAT Gateway costs and data transfer
