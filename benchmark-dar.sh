#!/bin/bash
set -e
time=0;
pauseTime=0;

if [ ! -e mozilla-central ] ; then
  hg clone https://hg.mozilla.org/mozilla-central
fi

DAR=${DAR:-dar}

purge () {
  if [ $(uname) == Darwin ] ; then
    sudo purge
  else
    sudo sh -c 'echo 1 >/proc/sys/vm/drop_caches'
    sudo sh -c 'echo 2 >/proc/sys/vm/drop_caches'
    sudo sh -c 'echo 3 >/proc/sys/vm/drop_caches'
  fi
}

logBegin () {
  time=$(date +%s)
}

logPause () {
  pauseTime=$(date +%s)
}

logResume () {
  time=$(( time + (`date +%s` - pauseTime) ))
  pauseTime=0;
}

logEnd () {
  op=$1 ; shift
  iter=$1 ; shift
  time=$(( `date +%s` - $time ))

  cat >> results-dar.txt << EOF
{
  "name": "$op",
  "time": $time,
  "iter": $iter,
  "metric": {
EOF

  while [ $# -ne 0 ] ; do
    type=$1 ; shift
    val=$1 ; shift

    if [ $type == size ] ; then
      val="    \"$val-filesize\": $(du -s $val | cut -f1)"
    else
      val="    \"$type\": $val"
    fi
    if [ $1 ] ; then
      val="$val,"
    fi
    echo "$val" >> results-dar.txt
  done

  echo "  }" >> results-dar.txt
  echo "}" >> results-dar.txt
  time=0;
  pauseTime=0;
}

reps="0 1 2"
compressors="bzip2 gzip lzo xz"
levels="1 5 6 7 9"

# 4 days of mozilla-central
# bbea1ed9586a -> bb5c1f7cc078

echo Starting Dar tests
for i in $reps ; do
  for c in $compressors ; do
    for l in 0 $levels ; do
      echo "Rep $i Compressor $c Level $l"

      # We want to use the same flag, which is nothing for no compression level
      # and -zbzip2:6 for bzip2 compression at level 6.
      if [ $l -ne 0 ] ; then
        zflag="-z${c}:${l}"
      else
        zflag=""
      fi
      # Generate base
      hg -R mozilla-central up -r bbea1ed9586a -C > /dev/null
      purge
      rm -f base.?.dar
      logBegin
      $DAR -c base $zflag -R $PWD/mozilla-central/
      logEnd "generate-dar-base" $i size base.7z level $l algo $c

      # Generate diff
      hg -R mozilla-central up -r bb5c1f7cc078 -C > /dev/null
      purge
      rm -rf diff.?.dar
      logBegin
      $DAR -c diff $zflag -R $PWD/mozilla-central/ -A base
      logEnd "generate-dar-diff" $i size diff.7z level $l algo $c

      # Extract base
      purge
      rm -rf output
      mkdir output
      logBegin
      $DAR -x base -O -R $PWD/output/mozilla-central  # -O supresses a warning about ownership
      logEnd "extract-dar-base" $i level $l algo $c

      # Extract diff
      logBegin
      $DAR -x diff -w -O -R $PWD/output/mozilla-central  # -w overwrites files 
      logEnd "extract-dar-diff" $i level $l algo $c
    done
  done
done

fn=results-dar-$(date +%s)
echo $fn
cp results-dar.txt $fn
