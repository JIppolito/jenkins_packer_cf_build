#!/bin/sh

#  updateStack.sh
#
#
#  Created by Jeffrey Ippolito on 5/28/15.
#  Converted to managed script by Don Luchini on 2015/06/28.

# Initialize our own variables:
stack_name=$(echo $JOB_NAME | sed 's/-update-stack//')
sleep_time=16

# Check if AWS CLI is installed
which aws > /dev/null 2>&1
if [ $? -ne 0 ]; then
echo "Error: AWS CLI is not installed"
exit 1
fi


#Check if $WORKSPACE/$job_name exists
if ! [ -e $WORKSPACE/$job_name ]
then
echo "Error: Could not find directory at $WORKSPACE/$job_name"
exit 1
fi

#Check if (http://packer.infra.enoc.cc:9292/api/v1/projects/${stack_name}/latest) is valid
if [ -z "$(curl -s --head http://packer.infra.enoc.cc:9292/api/v1/projects/${stack_name}/latest | head -n 1 | grep 'HTTP/1.[01] [23]..')" ]
then
echo "Error: http://packer.infra.enoc.cc:9292/api/v1/projects/${stack_name}/latest is not a valid address"
exit 1
fi

TIMESTAMP=$(date +%s)
AMI=$(curl -s "http://packer.infra.enoc.cc:9292/api/v1/projects/${stack_name}/latest?chef_environment=${stack_name}-${branch_name}" | jq -r .data.ami_id)

cd $WORKSPACE/$stack_name/

cat  ${stack_name}.json > ${stack_name}-${branch_name}-${TIMESTAMP}.json
RESULT=$?
if [ $RESULT -eq 0 ]; then
echo "Successfully created $WORKSPACE/$stack_name/${stack_name}-${branch_name}-${TIMESTAMP}.json"
else
echo "Failed to create ${stack_name}-${branch_name}-${TIMESTAMP}.json"
exit 1
fi

cd $WORKSPACE
echo AMI_ID=$AMI > propsfile
echo TIMESTAMP=$TIMESTAMP >> propsfile
echo JSON_FILE=${stack_name}-${branch_name}-${TIMESTAMP}.json >> propsfile

ls -al

aws configure set aws_access_key_id $AWS_ACCESS_KEY
aws configure set aws_secret_access_key $AWS_SECRET_KEY
aws configure set default.region us-east-1

cd $WORKSPACE/$stack_name/

# Ensure Jenkins has perms to list files in bucket
aws s3 ls enoc-cf-templates

aws s3 cp ${stack_name}-${branch_name}-${TIMESTAMP}.json s3://enoc-cf-templates
RESULT=$?
if [ $RESULT -eq 0 ]; then
echo "sleep $sleep_time"
sleep $sleep_time
else
echo "Failed to upload ${stack_name}-${branch_name}-${TIMESTAMP}.json to s3://enoc-cf-templates"
exit 1
fi

echo "Stack Before Update"
echo "##################"
aws cloudformation describe-stacks --stack-name ${stack_name}-${branch_name}

# list_stacks=$(aws cloudformation list-stacks)

# Attempt to get stack by Name. If it does not exist then create stack, else update existing stack
aws cloudformation describe-stacks --stack-name ${stack_name}-${branch_name} > log_file 2>&1
if [ $? != 0 ]; then
ERR=$(sed -n 2p < log_file)
# Verify that the error is because no stacks exist yet
if [ "$ERR" != "A client error (ValidationError) occurred when calling the DescribeStacks operation: Stack with id ${stack_name}-${branch_name} does not exist" ]; then
echo "Unfamiliar AWS Error enocountered"
echo $ERR
exit 1
else
echo "Stack does not exist"
fi

# Create Stack
aws cloudformation create-stack \
--stack-name ${stack_name}-${branch_name} \
--template-url https://s3.amazonaws.com/enoc-cf-templates/${stack_name}-${branch_name}-${TIMESTAMP}.json \
--capabilities CAPABILITY_IAM \
--parameters ParameterKey=TemplateRevision,ParameterValue=1 \
ParameterKey=AMI,ParameterValue=${AMI} \
ParameterKey=GITBRANCH,ParameterValue=${branch_name} \
ParameterKey=GITCOMMIT,ParameterValue=${git_commit}
RESULT=$?
if [ $RESULT -eq 0 ]; then
echo "Stack being created..."
else
echo "Failed to create stack ${stack_name}-${branch_name}-${TIMESTAMP}"
exit 1
fi
else

# Make sure stack is in a state that can be updated

stack_state=$(aws cloudformation describe-stacks --stack-name $stack_name-$branch_name | grep "StackStatus" | tr -d ",","\"",":"," " | cut -c 12-)
valid_states=(CREATE_FAILED ROLLBACK_IN_PROGRESS ROLLBACK_FAILED UPDATE_ROLLBACK_IN_PROGRESS UPDATE_ROLLBACK_FAILED)

if [[ $valid_states == *$stack_state ]]; then
echo "Error! The current state of the stack is $stack_state, which can't be updated."
exit 1
fi

# Update Stack
aws cloudformation update-stack \
--stack-name ${stack_name}-${branch_name} \
--template-url https://s3.amazonaws.com/enoc-cf-templates/${stack_name}-${branch_name}-${TIMESTAMP}.json \
--capabilities CAPABILITY_IAM \
--parameters ParameterKey=TemplateRevision,ParameterValue=1 \
ParameterKey=AMI,ParameterValue=${AMI} \
ParameterKey=GITBRANCH,ParameterValue=${branch_name} \
ParameterKey=GITCOMMIT,ParameterValue=${git_commit}
RESULT=$?
if [ $RESULT -eq 0 ]; then
echo "Stack being updated..."
else
echo "Failed to create stack ${stack_name}-${branch_name}-${TIMESTAMP}"
exit 1
fi
fi

# Makesure QA directory exists
if ! [ -d $branch_name ]; then
mkdir $branch_name
fi

# Move timestamped stack to the temp folder
mv ${stack_name}-${branch_name}-${TIMESTAMP}.json "$branch_name/${stack_name}-${branch_name}.json"
/usr/bin/git add "$branch_name/${stack_name}-${branch_name}.json"

# Check the git log for previous stack version
last_version=$(/usr/bin/git log|grep "#branch_name $branch_name"|cut -c 5-|head -n 1 | tr " " "\n"|sed -n '2p')

# If no previous stack tags exist commit 1.0.0
if [ -z "$last_version" ]; then
/usr/bin/git commit -m "#stack 1.0.0 #branch_name $branch_name #git_commit $git_commit"
echo "stack 1.0.0"
# Otherwise add 1 to previous stack version
else
IFS="."
set -- $last_version
/usr/bin/git commit -m "#stack $1.$2.$(($3+1)) #branch_name $branch_name #git_commit $git_commit"
echo "#stack $1.$2.$(($3+1))"
unset IFS
fi


