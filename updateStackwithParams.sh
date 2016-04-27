#!/bin/sh

#  updateStack.sh
#
#
#  Created by Jeffrey Ippolito on 5/28/15.
#

# Usage info
show_help() {
cat << EOF
Usage: ${0##*/} [-hnjfas]

-h          display this help then exit
-n          [Required] Stack Name defined in Cloudformation
-g          [Required] Jenkins Git Dir Name (need to get to $WORKSPACE/subdir directory
where cloudformation config JSON tempalate should be located)
-b          [Required] The git branch associated with the stack to be updated
-c          [Required] The git commit hash associated with this stack update
-a          [Required] AWS Access Key
-s          [Required] AWS Secrety Key.
-w          [Optional] Will wait x amount of time (seconds) between finished upload of
Cloudformation template to s3 and the template being retrievable
from S3. Default 15

EOF
}

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

# Initialize our own variables:
stack_name=""
gitdir=""
git_branch=""
git_commit=""
default_access_key=""
default_secret_key=""
sleep_time=""

OPTIND=1 # Reset is necessary if getopts was used previously in the script.  It is a good idea to make this local in a function.
while getopts "h:n:g:b:c:a:s:w:" opt; do
case "$opt" in
h)
show_help
exit 0
;;
n)  stack_name=$(echo ${OPTARG//[[:blank:]]/})
echo "-n was triggered, Parameter: $OPTARG" >&2
;;
g)  gitdir=$(echo ${OPTARG//[[:blank:]]/})
echo "-g was triggered, Parameter: $OPTARG" >&2
;;
b)  git_branch=$(echo ${OPTARG//[[:blank:]]/})
echo "-b was triggered, Parameter: $OPTARG" >&2
;;
c)  git_commit=$(echo ${OPTARG//[[:blank:]]/})
echo "-c was triggered, Parameter: $OPTARG" >&2
;;
a)  default_access_key=$(echo ${OPTARG//[[:blank:]]/})
echo "-a was triggered, Parameter: $OPTARG" >&2
;;
s)  default_secret_key=$(echo ${OPTARG//[[:blank:]]/})
echo "-s was triggered, Parameter: $OPTARG" >&2
;;
w)  sleep_time=$(echo ${OPTARG//[[:blank:]]/})
echo "-w was triggered, Parameter: $OPTARG" >&2
;;
'?')
show_help >&2
exit 1
;;
esac
done
shift "$((OPTIND-1))" # Shift off the options and optional --.

printf 'stackname=<%s> job_name=<%s>  default_access_key=<%s> default_secret_key=<%s> \nLeftovers:\n' \
"$stack_name" "$job_name" "AWS Access Key" "AWS Secret Key"
printf '<%s>\n' "$@"

if [ -z "$stack_name" ]
then
echo "-n (Stack Name) is required" >&2
exit 1
fi

if [ -z "$gitdir" ]
then
echo "-g (Jenkins gitdir) is required" >&2
exit 1
fi

if [ -z "$git_branch" ]
then
echo "-b (Git branch) is required" >&2
exit 1
fi

if [ -z "$git_commit" ]
then
echo "-c (Git commit) is required" >&2
exit 1
fi

if [ -z "$default_access_key" ]
then
echo "-a (AWS Access Key) is required" >&2
exit 1
fi

if [ -z "$default_secret_key" ]
then
echo "-s (AWS Secret Key) is required" >&2
exit 1
fi

if [ -z "$sleep_time" ]
then
sleep_time=15
fi

# Check if AWS CLI is installed
if ! [ -e /usr/local/bin/aws ]
then
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
AMI=$(curl -s http://packer.infra.enoc.cc:9292/api/v1/projects/${stack_name}/latest | jq -r .data.ami_id)
branch=$(echo $git_branch | sed -e 's/^origin\///g')

cd $WORKSPACE/$gitdir/

cat  ${stack_name}.json > ${stack_name}-${branch}-${TIMESTAMP}.json
RESULT=$?
if [ $RESULT -eq 0 ]; then
echo "Successfully created $WORKSPACE/$gitdir/${stack_name}-${branch}-${TIMESTAMP}.json"
else
echo "Failed to create ${stack_name}-${branch}-${TIMESTAMP}.json"
exit 1
fi

cd $WORKSPACE
echo AMI_ID=$AMI > propsfile
echo TIMESTAMP=$TIMESTAMP >> propsfile
echo JSON_FILE=${stack_name}-${branch}-${TIMESTAMP}.json >> propsfile

ls -al

/usr/local/bin/aws configure set aws_access_key_id $default_access_key
/usr/local/bin/aws configure set aws_secret_access_key $default_secret_key
/usr/local/bin/aws configure set default.region us-east-1

cd $WORKSPACE/$gitdir/

# Ensure Jenkins has perms to list files in bucket
/usr/local/bin/aws s3 ls enoc-cf-templates

/usr/local/bin/aws s3 cp ${stack_name}-${branch}-${TIMESTAMP}.json s3://enoc-cf-templates
RESULT=$?
if [ $RESULT -eq 0 ]; then
echo "sleep $sleep_time"
sleep $sleep_time
else
echo "Failed to upload ${stack_name}-${branch}-${TIMESTAMP}.json to s3://enoc-cf-templates"
exit 1
fi

echo "Stack Before Update"
echo "##################"
/usr/local/bin/aws cloudformation describe-stacks --stack-name ${stack_name}-${branch}

# list_stacks=$(/usr/local/bin/aws cloudformation list-stacks)

# Attempt to get stack by Name. If it does not exist then create stack, else update existing stack
/usr/local/bin/aws cloudformation describe-stacks --stack-name ${stack_name}-${branch} > log_file 2>&1
if [ $? != 0 ]; then
ERR=$(sed -n 2p < log_file)
# Verify that the error is because no stacks exist yet
if [ "$ERR" != "A client error (ValidationError) occurred when calling the DescribeStacks operation: Stack with id ${stack_name}-${branch} does not exist" ]; then
echo "Unfamiliar AWS Error enocountered"
echo $ERR
exit 1
else
echo "Stack does not exist"
fi

# Create Stack
/usr/local/bin/aws cloudformation create-stack \
--stack-name ${stack_name}-${branch} \
--template-url https://s3.amazonaws.com/enoc-cf-templates/${stack_name}-${branch}-${TIMESTAMP}.json \
--capabilities CAPABILITY_IAM \
--parameters ParameterKey=TemplateRevision,ParameterValue=1 \
ParameterKey=AMI,ParameterValue=${AMI} \
ParameterKey=GITBRANCH,ParameterValue=${branch} \
ParameterKey=GITCOMMIT,ParameterValue=${git_commit} 


RESULT=$?
if [ $RESULT -eq 0 ]; then
echo "Stack being created..."
else
echo "Failed to create stack ${stack_name}-${branch}-${TIMESTAMP}"
exit 1
fi
else

# Make sure stack is in a state that can be updated

stack_state=$(/usr/local/bin/aws cloudformation describe-stacks --stack-name $stack_name-$branch | grep "StackStatus" | tr -d ",","\"",":"," " | cut -c 12-)
valid_states=(CREATE_FAILED ROLLBACK_IN_PROGRESS ROLLBACK_FAILED UPDATE_ROLLBACK_IN_PROGRESS UPDATE_ROLLBACK_FAILED)

if [[ $valid_states == *$stack_state ]]; then
echo "Error! The current state of the stack is $stack_state, which can't be updated."
exit 1
fi

# Update Stack
/usr/local/bin/aws cloudformation update-stack \
--stack-name ${stack_name}-${branch} \
--template-url https://s3.amazonaws.com/enoc-cf-templates/${stack_name}-${branch}-${TIMESTAMP}.json \
--capabilities CAPABILITY_IAM \
--parameters ParameterKey=TemplateRevision,ParameterValue=1 \
ParameterKey=AMI,ParameterValue=${AMI} \
ParameterKey=GITBRANCH,ParameterValue=${branch} \
ParameterKey=GITCOMMIT,ParameterValue=${git_commit} 

RESULT=$?
if [ $RESULT -eq 0 ]; then
echo "Stack being updated..."
else
echo "Failed to create stack ${stack_name}-${branch}-${TIMESTAMP}"
exit 1
fi
fi

# Makesure QA directory exists
if ! [ -d $branch ]; then
mkdir $branch
fi

# Move timestamped stack to the temp folder
mv ${stack_name}-${branch}-${TIMESTAMP}.json "$branch/${stack_name}-${branch}.json"
/usr/bin/git add "$branch/${stack_name}-${branch}.json"

# Check the git log for previous stack version
last_version=$(/usr/bin/git log|grep "#branch $branch"|cut -c 5-|head -n 1 | tr " " "\n"|sed -n '2p')

# If no previous stack tags exist commit 1.0.0
if [ -z "$last_version" ]; then
/usr/bin/git commit -m "#stack 1.0.0 #branch $branch #git_commit $git_commit"
echo "stack 1.0.0"
# Otherwise add 1 to previous stack version
else
IFS="."
set -- $last_version
/usr/bin/git commit -m "#stack $1.$2.$(($3+1)) #branch $branch #git_commit $git_commit"
echo "#stack $1.$2.$(($3+1))"
unset IFS
fi
