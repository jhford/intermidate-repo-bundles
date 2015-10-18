#!/bin/bash
set -e
time=0;
pauseTime=0;

if [ ! -e mozilla-central ] ; then
  hg clone https://hg.mozilla.org/mozilla-central
fi

TAR=${TAR:-tar}
XZ=${XZ:-xz}
GZIP=${GZIP:-gzip}
GUNZIP=${GUNZIP:-gunzip}
BZIP2=${BZIP2:-bzip2}
BUNZIP2=${BUNZIP2:-bunzip2}
PIGZ=${PIGZ:-pigz}
UNPIGZ=${UNPIGZ:-unpigz}

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

  cat >> results.txt << EOF
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
    echo "$val" >> results.txt
  done

  echo "  }" >> results.txt
  echo "}" >> results.txt
  time=0;
  pauseTime=0;
}

reps="0 1 2 3 4 5 6 7 8 9"
xzlevels="0 2 4 5 6 6e 8 9 9e"
levels="1 3 5 6 7 9"
threads="1 2 4"

# 4 days of mozilla-central
# bbea1ed9586a -> bb5c1f7cc078

# Generating base
hg -R mozilla-central up -r bbea1ed9586a -C &> /dev/null
for i in $reps ; do
  purge
  logBegin
  ${TAR} -cpf base.tar --level=0 -g out.snar mozilla-central
  logEnd "generate-tar-base" $i size base.tar
done

# Generating diff
hg -R mozilla-central up -r bb5c1f7cc078 -C &> /dev/null
for i in $reps ; do
  purge
  logBegin
  ${TAR} -cpf diff.tar -g out.snar mozilla-central
  logEnd "generate-tar-diff" $i size diff.tar
done

# Extracting everything
for i in $reps ; do
  purge
  rm -rf output
  mkdir output
  logBegin
  ${TAR} -C output -xf base.tar -g /dev/null
  logEnd "extract-tar-base" $i size output
  logBegin
  ${TAR} -C output -xf diff.tar -g /dev/null
  logEnd "extract-tar-diff" $i size output
  rm -rf temp
done

cp base.tar base-comp.tar
cp diff.tar diff-comp.tar

for img in diff-comp base-comp ; do
  for i in $reps ; do
    for l in $xzlevels ; do
      for t in $threads ; do
        purge
        logBegin
        $XZ -T $t -${l} ${img}.tar
        logEnd "compress-xz-$img" $i size ${img}.tar.xz level $l threads $t
        purge
        logBegin
        $XZ -T $t --decompress ${img}.tar.xz
        logEnd "decompress-xz-$img" $i level $l threads $t
      done
    done

    for l in $levels ; do
      # Bzip2
      rm -f ${img}.tar.bz2
      purge
      logBegin
      $BZIP2 -$l ${img}.tar
      logEnd "compress-bzip2i-$img" $i size ${img}.tar.bz2 level $l
      purge
      logBegin
      $BUNZIP2 ${img}.tar.bz2
      logEnd "decompress-bzip2-$img" $i level $l

      # Gzip
      rm -f ${img}.tar.gz
      purge
      logBegin
      $GZIP -$l ${img}.tar
      logEnd "compress-gzip-$img" $i size ${img}.tar.gz level $l
      purge
      logBegin
      $GUNZIP ${img}.tar.gz
      logEnd "decompress-gzip-$img" $i level $l

      # pigz
      for t in $threads ; do
        rm -f ${img}.tar.gz
        purge
        logBegin
        $PIGZ -p ${t} -${l} ${img}.tar
        logEnd "compress-pigz-$img" $i size ${img}.tar.gz level $l threads $t
        purge
        logBegin
        $UNPIGZ -p ${t} ${img}.tar.gz
        logEnd "decompress-pigz-$img" $i level $l threads $t
      done
    done
  done
done

fn=results-$(date +%s)
echo $fn
cp results.txt $fn
