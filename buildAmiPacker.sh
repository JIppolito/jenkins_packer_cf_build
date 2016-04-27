#!/bin/bash

set -x
set -e

echo "Parameters:"
echo -e "\tReprovision: $reprovision"
echo -e "\tBranch name: $branch_name"
echo -e "\tArtifact version: $artifact_version"
echo -e "\tOrigin Git commit: $origin_git_commit"

TEMPLATE=$JOB_NAME
CHEF_ENVIRONMENT=$JOB_NAME-$branch_name

cd $WORKSPACE/$TEMPLATE

# create Packer template with Racker
echo "Creating Packer template with Racker"
echo "Ruby version: $(chruby-exec 2.1 -- ruby --version)"
echo "Racker version: $(echo -e "require 'racker' \\n puts Racker::Version.version()" | chruby-exec 2.1 -- ruby)"

PACKER_RUN_LIST="$JENKINS_HOME/racker_base.rb"
if [ "$reprovision" == "true" ]; then
  # get the latest AMI name
  if [ "x$branch_name" != "x" ]; then
    export AMI=$(curl "http://localhost:9292/api/v1/projects/$TEMPLATE/latest?chef_environment=$CHEF_ENVIRONMENT" | jq -r .data.ami_id)
  else
    export AMI=$(curl http://localhost:9292/api/v1/projects/$TEMPLATE/latest | jq -r .data.ami_id)
  fi

  # add the AMI shim to the run list if one was passed back
  if [ "$AMI" != "null" ]; then
    PACKER_RUN_LIST="$PACKER_RUN_LIST $JENKINS_HOME/ami_shim.rb"
  else
    echo 'No AMI returned from AMI Manager - not reprovisioning.'
  fi
fi

# Dynamically create an environment, if specified
if [ "x$branch_name" != "x" ]; then
  # Template the branch with appropriate name and deployablei
  echo "@artifact_version='$artifact_version'" > context.rb
  echo "@branch_name='$branch_name'" >> context.rb
  chruby-exec ruby-2.1 -- erubis -f context.rb env_template.rb > $CHEF_ENVIRONMENT.json

  # Upload it to the Chef server
  knife environment from file $CHEF_ENVIRONMENT.json

  # Add it to the Racker run list
  PACKER_RUN_LIST="$PACKER_RUN_LIST $JENKINS_HOME/env_shim.rb"
fi 
PACKER_RUN_LIST="$PACKER_RUN_LIST $TEMPLATE.rb"

chruby-exec 2.1 -- racker $PACKER_RUN_LIST $TEMPLATE.json
echo

# validate Packer template
echo Validating Packer template
echo "Packer version: $(/usr/bin/packer version)"
/usr/bin/packer validate $TEMPLATE.json
echo
# echo $(cat $TEMPLATE.json)
cat $TEMPLATE.json | python -m json.tool

# build the image
echo "Running the 'amazon-ebs' builder task"
/usr/bin/packer build -only=amazon-ebs -color=false $TEMPLATE.json


