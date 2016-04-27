/usr/local/bin/aws configure set aws_access_key_id $AWS_ACCESS_KEY
/usr/local/bin/aws configure set aws_secret_access_key $AWS_SECRET_KEY
/usr/local/bin/aws configure set default.region us-east-1

stack_name=$(echo $JOB_NAME | sed 's/-update-stack//')

arn=$(/usr/local/bin/aws cloudformation describe-stack-resources --stack-name ${stack_name}-${branch_name} | jq .StackResources[0].PhysicalResourceId)
elbname=$(/usr/local/bin/aws cloudformation describe-stack-resources --stack-name `echo "${arn//\"}"` --logical-resource-id ELB | jq .StackResources[0].PhysicalResourceId)
dnsName=$(/usr/local/bin/aws elb describe-load-balancers --load-balancer-name `echo "${elbname//\"}"` | jq .LoadBalancerDescriptions[0].DNSName)

echo $dnsName





