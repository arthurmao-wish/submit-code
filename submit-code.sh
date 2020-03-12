#!/usr/bin/env bash
set -o errexit #abort if any command fails

#### default args ####
me=$(basename "$0")
current_branch=$(git rev-parse --abbrev-ref HEAD)
current_user=$(git config user.name)
remote_branch="${current_user}-${current_branch}"
tmp_prefix="_tmp"
auto_fetch_threshold=3600

# alias for --merge
alias=$(cat <<-END
hotfix:master,wishpost_release_candidate,wishpost_production
release:master,wishpost_release_candidate
END
)
alias_hotfix="master,wishpost_release_candidate,wishpost_production"
alias_release="master,wishpost_release_candidate"
#####

help_message="\
Usage: $me [<options>]
Create pull request based on your current branch
Set default value in config file ~/.submit_code_config

Options:
  -h, --help                                  Show this help information.
  -c, --create <NAME>                         Create new branch for your project
  -p, --pull-request                          Submit Pull Request
  -r, --reviewer <USERS>                      Add reviewer for your pull request
  -a, --assign <USERS>                        Add assignee for your pull request
  -o, --browse                                Browse change
  -m, --merge <TARGET>                        Merge changes to <TARGET>, <TARGET> could be a branch list (split by ',') or an alias (start with ':')
                                              Alias can be defined in ~/.submit_code_config, starting with 'alias_' prefix.
                                              Default alias:
                                                  :release = wishpost_release_candidate
                                                  :hotfix = wishpost_production
      Example: -m :hotfix
               -m master,wishpost_release_candidate

  --skip_fetch                                Skip fetching latest code
  --clean                                     Clean uncommited changes
"

echo_green() {
  echo -e "\033[32m$1\033[0m"
}
echo_red() {
  echo -e "\033[31m$1\033[0m"
}
echo_yellow() {
  echo -e "\033[33m$1\033[0m"
}

## Getting machine env
unameOut="$(uname -s)"
case "${unameOut}" in
    Linux*)     machine=Linux;;
    Darwin*)    machine=Mac;;
    CYGWIN*)    machine=Cygwin;;
    MINGW*)     machine=MinGw;;
    *)          machine="UNKNOWN:${unameOut}"
esac

echo_green "Git user: ${current_user}, machine ${machine}"

parse_args() {
  # Set args from a local environment file.
  if [ -e "$HOME/.submit_code_config" ]; then
    source $HOME/.submit_code_config
  fi

  current_branch=`git rev-parse --abbrev-ref HEAD`
  

  # Parse arg flags
  # If something is exposed as an environment variable, set/overwrite it
  # here. Otherwise, set/overwrite the internal variable instead.
  while : ; do
    if [[ $1 = "-h" || $1 = "--help" ]]; then
      echo_yellow "$help_message"
      return 0
    elif [[ $1 = "-c" || $1 = "--create" ]]; then
      shift
      create_branch=$1
      shift
    elif [[ $1 = "--clean" ]]; then
      clean_changes=true
      shift
    elif [[ $1 = "-p" || $1 = "--pull_request" ]]; then
      pull_request=true
      shift
    elif [[ $1 = "-o" || $1 = "--browse" ]]; then
      browse=true
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
      shift
      merge_target=$1
      # echo "${alias_name}"
      if [[ $1 == :* ]]; then
        alias_name=$(echo "$1" | sed -En "s/:(.+)/\1/p")
        push_branch=$(echo "${alias}" | grep "${alias_name}:" | sed -En "s/.+:(.+)/\1/p")
        if [ -z $push_branch ]; then
          echo_red "Error: Alias '$1' not defined."
        fi
      else
        push_branch=$1
      fi
      echo_green "Merge branches: ${push_branch}"
      shift
    elif [[ $1 = "--skip_fetch" ]]; then
      skip_fetch=true
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
    echo_yellow "Reviewer: $reviewer"
  fi
  if [ $assign ]; then
    hub_args="$hub_args -a $assign"
    echo_yellow "Assignee: $assign"
  fi
  if [ $browse ]; then
    hub_args="$hub_args -o"
    echo_yellow "Browse: $browse"
  fi
}

fetch_latest_code() {
  force_fetch=${1:--1}
  if git fwhen > /dev/null; then
    echo ""
  else
    echo_green "Config 'git fwhen' alias..."
    if [[ ${machine} == "Mac" ]]; then
      git config --global alias.fwhen '!stat -f %m .git/FETCH_HEAD'
    elif [[ ${machine} == "Linux" ]]; then
      git config --global alias.fwhen '!stat -c %Y .git/FETCH_HEAD'
    fi
  fi
  if [ ${force_fetch} -lt 0 ]; then
    current_ts=$(date +%s);
    last_fetch_ts=$(git fwhen);
    fetch_interval=$(expr ${current_ts} - ${last_fetch_ts})
    need_fetch=$(expr ${fetch_interval} - ${auto_fetch_threshold})
    echo_yellow "${fetch_interval} seconds since last git fetch..."
  else
    need_fetch=1
  fi
  if [ ${need_fetch} -lt 0 ]; then
    echo_green "Fetching latest code... [skipped]"
    return 0
  fi

  target_rebase_branch=$1
  if [ -z $skip_fetch ]; then
    echo_green "Fetching latest code..."
    git remote prune origin
    git fetch origin
  else
    echo_green "Fetching latest code... [skipped]"
  fi
}

create_pull_request() {
  fetch_latest_code 1
  git rebase origin/master
  echo_green "Pushing code to remote branch $remote_branch..."
  git push origin $current_branch:$remote_branch --force
  echo_green "Creating pull request..."
  pr_exists=$(hub pr list -h ${remote_branch} -f %U)
  if [ $pr_exists ]; then
    echo_green "Pull request already exists, updating..."
    echo_green $pr_exists
    if [ $browse ]; then
      hub pr show -h ${remote_branch}
    fi
  else
    build_hub_args
    echo_green "hub pull-request $hub_args"
    hub pull-request $hub_args
  fi
}

create_tmp_branch_from_remote() {
  target_remote=$1
  if git show-ref --verify --quiet "refs/remotes/origin/${target_remote}"; then
    tmp_branch="${tmp_prefix}_${target_remote}"
    if git show-ref --verify --quiet "refs/heads/${tmp_branch}"; then
      echo_green "Cleaning tmp branch..."
      git branch -D ${tmp_branch}
    fi
    echo_green "Creating branch ${tmp_branch} from origin/${target_remote}..."
    git checkout -b ${tmp_branch} origin/${target_remote}
    return 0
  else
    return 1
  fi
}

git_push_retry() {
  current_branch=$1
  target_branch=$2
  retry_time=${3:-2}
  n=0
  until [ $n -ge ${retry_time} ]
  do
    echo_green "git push origin ${current_branch}:${target_branch} ..."
    $(git push origin ${current_branch}:${target_branch}) && break
    echo_yellow "Push failed, fetch latest code and retry..."
    git fetch origin
    git rebase origin/${target_branch}
    git reset origin/${target_branch} --hard
    git merge 
    n=$[$n+1]
  done
  echo_red "Error: push failed"
  return 1
}

push_to_branch() {
  fetch_latest_code
  echo_green "Creating from remote branch..."
  if create_tmp_branch_from_remote ${remote_branch}; then
    commit_msg=$(git log -1 --pretty=%B)
    commit_hash="$(git log -1 --pretty=%H)"
    commit_suffix="(#$(hub pr list -h ${remote_branch} -f %I))"
  else
    return 1
  fi

  echo_green "Merging changes..."
  for i in $(echo $push_branch | sed "s/,/ /g")
  do
    if create_tmp_branch_from_remote $i; then
      if [ $i = "master" ]; then
        echo_yellow "git merge ${tmp_prefix}_${remote_branch} -m '${commit_msg} ${commit_suffix}'"
        git merge ${tmp_prefix}_${remote_branch} -m "${commit_msg} ${commit_suffix}"
        echo_green "git push origin ${tmp_prefix}_$i:$i ..."
        $(git push origin ${tmp_prefix}_$i:$i) && continue
        echo_yellow "push failed, sync latest code and retry..."
        git fetch origin
        git rebase origin/master
        git reset origin/master --hard
        git merge ${tmp_prefix}_${remote_branch} -m "${commit_msg} ${commit_suffix}"
        $(git push origin ${tmp_prefix}_$i:$i) && continue
        echo_yellow "Push master failed, exit.."
        return 1
      else
        echo_yellow "If cherry-pick failed with conflicts, please fix it then manually cherry/push to the branch. Commit ID:${commit_hash}"
        git cherry-pick ${commit_hash} --allow-empty
        git commit -m "${commit_msg} ${commit_suffix}" --amend --no-verify
        $(git push origin ${tmp_prefix}_$i:$i) && continue
        echo_yellow "push failed, sync latest code and retry..."
        git fetch origin
        git rebase origin/master
        $(git push origin ${tmp_prefix}_$i:$i) && continue
        echo_yellow "Push master failed, exit.."
        return 1
      fi
    else
      echo_yellow "Remote branch ${remote_branch} not exists, skipping..."
    fi
  done
  git checkout ${current_branch}
  echo_green "Done."
}

create_new_branch() {
  fetch_latest_code
  git checkout -b ${create_branch} origin/master;
}

git_clean() {
  git clean -fx
  git clean -fd
  git reset --hard
}

main() {
  parse_args "$@"
  if [ $create_branch ]; then
    create_new_branch
  elif [ $pull_request ]; then
    create_pull_request
  elif [ $push_branch ]; then
    push_to_branch
  elif [ $clean_changes ]; then
    git_clean
  else
    echo_yellow "$help_message"
  fi
}

main "$@"