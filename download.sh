#!/bin/bash

function usage() {
  echo "Usage: `basename $0` <input>"
  exit 1
}

[ -f "$1" ] || usage

for l in `grep -v "^#" $1`; do
  # 2007-09|http://xxxx
  arr=(`echo $l | tr "|" " "`)

  dir=${arr[0]} # 2007-09
  url=${arr[1]} # http://xxx

  # create dir if not exist
  [ -d "$dir" ] || mkdir $dir

  # download
  wget -P $dir -nc --content-disposition -t 3 $url
done
