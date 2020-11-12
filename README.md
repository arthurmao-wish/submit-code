# submit-code
Tools to submit your code. Including create pull-request, push to release candidate and production

# Create new branch on your local repo

``` shell
submit-code.sh -c <branch name>
```

# Create pull request

``` shell
# After commit change
submit-code.sh -p -r <reviewers, split by comma> -a <assign>

# Default reviewer and assignee can be configed in file: ~/.submit_code_config
# Example:
$ cat ~/.submit_code_config
reviewer=cherishqi,frankliu-wish,sherryhuang-wish
assign=arthurmao-wish
slack_bot_url=https://xx/xxx
```

# Update pull request

``` shell
# Commit change and run again
submit-code.sh -p
```

# Merge change

``` shell
# Commit change and run again
submit-code.sh -m <target branch>

# Merge master only
submit-code.sh -m master

# Merge master and push release candidate
submit-code.sh -m :release

# Merge master, push release candidate and production
submit-code.sh -m :hotfix
```

# Other options

See `submit-code.sh --help`
