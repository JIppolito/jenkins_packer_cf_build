#!/bin/sh


#ran successfully on the command line:  ./getStackStatus.sh -n stampede-dummy -a myawsaccesskey -s myawssecretkey

# Usage info
show_help() {
cat << EOF
Usage: ${0##*/} [-hnasw]

    -h          display this help then exit
    -n          [Required] Stack Name defined in Cloudformation
    -b          [Required] The git branch associated with the stack to be updated
    -a          [Required] AWS Access Key
    -s          [Required] AWS Secrety Key.
    -w          [Optional] Max wait period to wait for an anwser from AWS. Default 600 seconds

EOF
}

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

# Initialize our own variables:
stack_name=""
git_branch=""
default_access_key=""
default_secret_key=""
wait_period=600

OPTIND=1 # Reset is necessary if getopts was used previously in the script.  It is a good idea to make this local in a function.
while getopts "h:n:b:a:s:w:" opt; do
    case "$opt" in
        h)
            show_help
            exit 0
            ;;
        n)  stack_name=$(echo ${OPTARG//[[:blank:]]/})
            echo "-n was triggered, Parameter: $OPTARG" >&2
            ;;
        b)  git_branch=$(echo ${OPTARG//[[:blank:]]/})
            echo "-b was triggered, Parameter: $OPTARG" >&2
            ;;
        a)  default_access_key=$(echo ${OPTARG//[[:blank:]]/})
            echo "-a was triggered, Parameter: $OPTARG" >&2
            ;;
        s)  default_secret_key=$(echo ${OPTARG//[[:blank:]]/})
            echo "-s was triggered, Parameter: $OPTARG" >&2
            ;;
        w)  wait_period=$(echo ${OPTARG//[[:blank:]]/})
            echo "-w was triggered, Parameter: $OPTARG" >&2
            ;;
        '?')
            show_help >&2
            exit 1
            ;;
    esac
done
shift "$((OPTIND-1))" # Shift off the options and optional --.

printf 'stackname=<%s> git_branch=<%s> wait_period=<%s> default_access_key=<%s> default_secret_key=<%s>\nLeftovers:\n' "$stack_name" "$git_branch" "$wait_period" "default_access_key" "default_secret_key"
printf '<%s>\n' "$@"

if [ -z "$stack_name" ]
then
echo "-n (Stack Name) is required" >&2
exit 1
fi


if [ -z "$git_branch" ]
then
echo "-b (Git branch) is required" >&2
exit 1
fi


if [ -z "$default_access_key" ]
then
echo "-a (AWS Access Key ) is required" >&2
exit 1
fi


if [ -z "$default_secret_key" ]
then
echo "-s (AWS Secret Key ) is required" >&2
exit 1
fi

/usr/local/bin/aws configure set aws_access_key_id $default_access_key
/usr/local/bin/aws configure set aws_secret_access_key $default_secret_key
/usr/local/bin/aws configure set default.region us-east-1


NOW=$(date +%s)
WAIT_PERIOD=600
END_TIME=$(($WAIT_PERIOD + $NOW))

branch=$(echo $git_branch | sed -e 's/^origin\///g')

echo "Start Time: $NOW"
echo "End Time: $END_TIME"

invalid_states=(CREATE_FAILED ROLLBACK_IN_PROGRESS ROLLBACK_FAILED ROLLBACK_COMPLETE UPDATE_ROLLBACK_IN_PROGRESS UPDATE_ROLLBACK_FAILED UPDATE_ROLLBACK_COMPLETE)
valid_states=(UPDATE_COMPLETE CREATE_COMPLETE)


while [ "$NOW" -lt "$END_TIME" ]
do
stacks=$(/usr/local/bin/aws cloudformation describe-stacks --stack-name ${stack_name}-${branch})
RESULT=$?
if [ $RESULT -eq 0 ]; then
status=$(echo ${stacks} | jq '.Stacks | .[].StackStatus' | tr -d "\"" | tr -d "\'")
if [[ $valid_states == *$status ]]; then
echo "Updated Successfully: Status - ${status}"
exit 0
elif [[ $invalid_states == *$status ]]; then
echo "FAILED to Update: Status - ${status}"
exit 1
else
echo "Status: ${status}"
sleep 5
NOW=$(date +%s)
fi
else
echo "Failed to describe ${stack_name}-${branch}"
exit 1
fi
done

echo "TIMOUT!! FAILED to Update: Status - ${status}"
exit 1
