#!/usr/bin/env bash
set -o errexit #abort if any command fails
me=$(basename "$0")
current_branch=$(git rev-parse --abbrev-ref HEAD)
current_user=$(git config user.name)

remote_branch="${current_user}-${current_branch}"

help_message="\
Usage: $me [<options>]
Create pull request based on your current branch
Set default value in config file ~/.submit_code_config

Options:
  -h, --help                           Show this help information.
  -p, --pull_request                   Create pull request on github
  -r, --reviewer <USERS>               Add reviewer for your pull request
  -a, --assign <USERS>                 Add assignee for your pull request
  -o, --browse                         Browse change
  -m, --merge                          Merge your pull request.
  -b, --push_branch <BRANCH>           Push your change to other branch. (For hotfix / quick release)
"

parse_args() {
  # Set args from a local environment file.
  if [ -e ".submit_code_config" ]; then
    source .submit_code_config
  fi

  current_branch=`git rev-parse --abbrev-ref HEAD`
  

  # Parse arg flags
  # If something is exposed as an environment variable, set/overwrite it
  # here. Otherwise, set/overwrite the internal variable instead.
  while : ; do
    if [[ $1 = "-h" || $1 = "--help" ]]; then
      echo "$help_message"
      return 0
    elif [[ $1 = "-o" || $1 = "--browse" ]]; then
      browse=true
      shift
    elif [[ $1 = "-p" || $1 = "--pull_request" ]]; then
      pull_request=true
      shift
    elif [[ $1 = "-r" || $1 = "--reviewer" ]]; then
      shift
      reviewer=$1
      shift
    elif [[ $1 = "-a" || $1 = "--assign" ]]; then
      shift
      assign=$1
      shift
    elif [[ $1 = "-m" || $1 = "--merge" ]]; then
      merge=true
      shift
    elif [[ $1 = "-b" || $1 = "--push_branch" ]]; then
      shift
      push_branch=$1
      shift
    else
      break
    fi
  done
}

build_hub_args() {
  hub_args="-h ${remote_branch}"
  if [ $reviewer ]; then
    hub_args="$hub_args -r $reviewer"
    echo "Reviewer: $reviewer"
  fi
  if [ $assign ]; then
    hub_args="$hub_args -a $assign"
    echo "Assignee: $assign"
  fi
  if [ $browse ]; then
    hub_args="$hub_args -o"
    echo "Browse: $browse"
  fi
}

create_pull_request() {
  echo "Pushing code to remote branch $remote_branch.."
  git push origin $current_branch:$remote_branch --force
  echo "Creating pull request.."
  pr_exists=$(hub pr list -h ${remote_branch} -f %U)
  if [ $pr_exists ]; then
    echo "Pull request already exists..."
    echo $pr_exists
    if [ $browse ]; then
      hub pr show -h ${remote_branch}
    fi
  else
    build_hub_args
    echo "hub pull-request $hub_args"
    hub pull-request $hub_args
  fi
}

merge_code() {
  echo "Merging code change.."
  echo "git fetch origin"
  git fetch origin
  echo "git checkout origin/${remote_branch}"
  echo "git merge --no-ff origin/master"
  git merge --no-ff origin/master
  git push origin master
}

main() {
  parse_args "$@"
  if [ $pull_request ]; then
    create_pull_request
  elif [ $merge ]; then
    merge_code
  else
    echo "$help_message"
  fi
}

main "$@"

