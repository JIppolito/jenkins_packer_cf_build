#!/bin/sh

# Usage info
show_help() {
cat << EOF
Usage: ${0##*/} [-hnjfas]

-p        [Required] Name of the project associated with the stack
-b        [Required] Name of the git branch associated with the stack
-a        [Required] AWS Access Key
-s        [Required] AWS Secrety Key.
        
-w        [Optional] Will wait x amount of time (seconds) between finished
                     upload of Cloudformation template to s3 and the template
                     being retrievable from S3. Default 15

EOF
}

# Intialize variables
project_name=""
branch_name=""
aws_access_key=""
aws_secret_key=""
wait_time=15

OPTIND=1 # Reset in case getopts has been used previously in the shell.
while getopts "p:b:a:s:w:" opt; do
  case "$opt" in
    p) project_name=$(echo ${OPTARG//[[:blank:]]/})
    echo "-p was triggered, Parameter: $OPTARG" >&2
    ;;
    b) branch_name=$(echo ${OPTARG//[[:blank:]]/})
    echo "-b was triggered, Parameter: $OPTARG" >&2
    ;;
    a) aws_access_key=$(echo ${OPTARG//[[:blank:]]/})
    echo "-a was triggered, Parameter: $OPTARG" >&2
    ;;
    s) aws_secret_key=$(echo ${OPTARG//[[:blank:]]/})
    echo "-s was triggered, Parameter: $OPTARG" >&2
    ;;
    w) wait_time=$(echo ${OPTARG//[[:blank:]]/})
    echo "-w was triggered, Parameter: $OPTARG" >&2
    ;;
  esac
done

# Check for required arguments
if [ -z "$project_name" ]; then
  echo "Error! missing required argument -p project_name"
  exit 1
fi
if [ -z "$branch_name" ]; then
  echo "Error! missing required argument -b branch_name"
  exit 1
fi
if [ -z "$aws_access_key" ]; then
  echo "Error! missing required argument -a aws_access_key"
  exit 1
fi
if [ -z "$aws_secret_key" ]; then
  echo "Error! missing required argument -s aws_secret_key"
  exit 1
fi

branch=$(echo $git_branch | sed -e 's/^origin\///g')

# Makes sure that a template file exists for the branch
if ! [ -e $branch/$project_name-$branch.json ]; then
  echo "Error! No stack template found at $branch/$project_name-$branch.json"
  exit 1
fi

#Get previous commit hash for stack template
last_commit=$(/usr/bin/git log --pretty=format:'%H' $branch/$project_name-$branch.json | sed -n '2p')
if [ -z "$last_commit" ]; then
  echo "Error! No previous version of the stack could be found."
  exit 1
fi
# Git checkout previous commit for $branch/stack-$branch.json
/usr/bin/git checkout "$last_commit" $branch/$project_name-$branch.json

# Configure AWS
/usr/local/bin/aws configure set aws_access_key_id $aws_access_key
/usr/local/bin/aws configure set aws_secret_access_key $aws_secret_key
/usr/local/bin/aws configure set default.region us-east-1

# Make sure that stack exists 
/usr/local/bin/aws cloudformation describe-stacks --stack-name ${project_name}-${branch} > log_file 2>&1
if [ $? != 0 ]; then
  ERR=$(sed -n 2p < log_file)
  # Verify that the error is because no stacks exist yet
  if [ "$ERR" != "A client error (ValidationError) occurred when calling the DescribeStacks operation: Stack:${project_name}-${branch} does not exist" ]; then
    echo "Unfamiliar AWS Error enocountered"
    echo $ERR
    exit 1
  else
    echo "Error! Stack ${project_name}-${branch} does not exist."
    exit 1
  fi
fi 

# Make sure stack is in a state which can rollback
stack_state=$(/usr/local/bin/aws cloudformation describe-stacks --stack-name $stack_name-$branch | grep "StackStatus" | tr -d ",","\"",":"," " | cut -c 12-)
valid_states=(CREATE_FAILED ROLLBACK_IN_PROGRESS ROLLBACK_FAILED ROLLBACK_COMPLETE UPDATE_ROLLBACK_IN_PROGRESS UPDATE_ROLLBACK_FAILED)

if [[ $valid_states == *$stack_state ]]; then
echo "Error! The current state of the stack is $stack_state, which can't be updated."
exit 1
fi


TIMESTAMP=$(date +%s)
/usr/local/bin/aws s3 cp ${branch_name}/${project_name}-${branch}.json s3://enoc-cf-templates/${project_name}-${branch}-ROLLBACK-${TIMESTAMP}.json
sleep $wait_time


# Update stack using that version of the stack
/usr/local/bin/aws cloudformation update-stack \
    --stack-name ${project_name}-${branch} \
    --template-url https://s3.amazonaws.com/enoc-cf-templates/${project_name}-${branch}-ROLLBACK-${TIMESTAMP}.json \
    --parameters ParameterKey=TemplateRevision,ParameterValue=1 \
ParameterKey=AMI,ParameterValue=${AMI} \
ParameterKey=GITBRANCH,ParameterValue=${branch} \
ParameterKey=GITCOMMIT,ParameterValue=${last_commit}
RESULT=$?
if [ $RESULT -eq 0 ]; then
echo "Stack being updated..."
else
echo "Failed to rollback stack ${stack_name}-${branch}-${TIMESTAMP}"
exit 1
fi


