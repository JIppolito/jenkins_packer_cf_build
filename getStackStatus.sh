#!/bin/sh

#  getStackStatus.sh
#
#
#  Created by Jeffrey Ippolito.
#  Converted to managed script by Don Luchini on 2015/06/28.

aws configure set aws_access_key_id $AWS_ACCESS_KEY
aws configure set aws_secret_access_key $AWS_SECRET_KEY
aws configure set default.region us-east-1


NOW=$(date +%s)
WAIT_PERIOD=600
END_TIME=$(($WAIT_PERIOD + $NOW))

stack_name=$(echo $JOB_NAME | sed 's/-update-stack//')

echo "Start Time: $NOW"
echo "End Time: $END_TIME"

invalid_states=(CREATE_FAILED ROLLBACK_IN_PROGRESS ROLLBACK_FAILED ROLLBACK_COMPLETE UPDATE_ROLLBACK_IN_PROGRESS UPDATE_ROLLBACK_FAILED UPDATE_ROLLBACK_COMPLETE)
valid_states=(UPDATE_COMPLETE CREATE_COMPLETE)


while [ "$NOW" -lt "$END_TIME" ]
do
stacks=$(aws cloudformation describe-stacks --stack-name ${stack_name}-${branch_name})
RESULT=$?
if [ $RESULT -eq 0 ]; then
status=$(echo ${stacks} | jq '.Stacks | .[].StackStatus' | tr -d "\"" | tr -d "\'")
if [[ "${valid_states[@]}" =~ "${status}" ]]; then
#if [[ $valid_states == *$status* ]]; then
echo "Updated Successfully: Status - ${status}"
exit 0
elif [[ "${invalid_states[@]}" =~ "${status}" ]]; then
echo "FAILED to Update: Status - ${status}"
exit 1
else
echo "Status: ${status}"
sleep 5
NOW=$(date +%s)
fi
else
echo "Failed to describe ${stack_name}-${branch_name}"
exit 1
fi
done

echo "TIMEOUT!! FAILED to Update: Status - ${status}"
exit 1



