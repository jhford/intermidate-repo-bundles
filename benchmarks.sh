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
SZA=${SZA:-7za}

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

# 7-Zip: http://a32.me/2010/08/7zip-differential-backup-linux-windows/
# NOTE: 7-Zip doesn't store owner/group, but since our repos don't
#       either, we should be fine!

echo Starting 7-zip tests
for i in $reps ; do
  for l in 0 $levels ; do
    echo rep $i level $l
    # Generate base
    hg -R mozilla-central up -r bbea1ed9586a -C > /dev/null
    purge
    logBegin
    ${SZA} -bd -t7z -mx=${l} a base.7z mozilla-central > /dev/null
    logEnd "generate-7zip-base" $i size base.7z level $l

    # Generate diff
    hg -R mozilla-central up -r bb5c1f7cc078 -C > /dev/null
    purge
    logBegin
    ${SZA} -bd -t7z -mx=0 u base.7z -u- -up0q3x2z0\!diff.7z mozilla-central > /dev/null
    logEnd "generate-7zip-diff" $i size base.7z level $l

    # Extract base
    purge
    rm -rf output
    mkdir output
    logBegin
    (cd output && ${SZA} x base.7z > /dev/null)
    logEnd "extract-7z-base" $i level $l

    # Extract diff
    logBegin
    (cd output && ${SZA} x diff.7z -aoa  -y > /dev/null)
    logEnd "extract-7z-diff" $i level $l
  done
done

echo Starting GNU Tar tests 
for i in $reps ; do
  echo rep $i
  # Generate tar base archive
  hg -R mozilla-central up -r bbea1ed9586a -C > /dev/null
  purge
  logBegin
  ${TAR} -cpf base.tar --level=0 -g out.snar mozilla-central
  logEnd "generate-tar-base" $i size base.tar

  # Generate tar diff archive
  hg -R mozilla-central up -r bb5c1f7cc078 -C > /dev/null
  purge
  logBegin
  ${TAR} -cpf diff.tar -g out.snar mozilla-central
  logEnd "generate-tar-diff" $i size diff.tar

  # Extract tar base archive
  purge
  rm -rf output
  mkdir output
  logBegin
  ${TAR} -C output -xf base.tar -g /dev/null
  logEnd "extract-tar-base" $i size output

  # Extract tar diff archive
  logBegin
  ${TAR} -C output -xf diff.tar -g /dev/null
  logEnd "extract-tar-diff" $i size output
done


echo Starting tar compressor tests

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
