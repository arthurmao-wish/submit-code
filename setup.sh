#!/bin/bash
unameOut="$(uname -s)"
case "${unameOut}" in
    Linux*)     machine=Linux;;
    Darwin*)    machine=Mac;;
    CYGWIN*)    machine=Cygwin;;
    MINGW*)     machine=MinGw;;
    *)          machine="UNKNOWN:${unameOut}"
esac
echo "Env: $machine"
if [ $machine = "Mac" ]; then
  brew update
elif []; then
  if [ -f /etc/lsb-release ]; then
    apt-get update
  else
    echo "Error: Only support UBUNTU"
  fi
fi
