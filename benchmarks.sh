#!/bin/bash
set -e
time=0;
pauseTime=0;

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
      val="    \"$type\": $(du -s $val | cut -f1)"
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

reps="0" # 1 2 3 4 5 6 7 8 9
xzlevels="" #"0 0e 1 1e 2 2e 3 3e 4 4e 5 5e 6 6e 7 7e 8 8e 9 9e"
levels="1 2 3 4 5 6 7 8 9"
threads="1 2 4"

# 4 days of mozilla-central
# bbea1ed9586a -> bb5c1f7cc078

# Generating base
hg -R mozilla-central up -r bbea1ed9586a -C
for i in $reps ; do
  sudo purge
  logBegin
  gtar -cpf base.tar --level=0 -g out.snar mozilla-central
  logEnd "generate-tar-base" $i size base.tar
done

# Generating diff
hg -R mozilla-central up -r bb5c1f7cc078 -C
for i in $reps ; do
  sudo purge
  logBegin
  gtar -cpf diff.tar -g out.snar mozilla-central
  logEnd "generate-tar-diff" $i size diff.tar
done

# Extracting everything
for i in $reps ; do
  sudo purge
  rm -rf output
  mkdir output
  logBegin
  gtar -C output -xf base.tar -g /dev/null
  logEnd "extract-tar-base" $i size output
  logBegin
  gtar -C output -xf diff.tar -g /dev/null
  logEnd "extract-tar-diff" $i size output
  rm -rf temp
done

cp base.tar base-comp.tar
cp diff.tar diff-comp.tar

for img in diff-comp base-comp ; do
  for i in $reps ; do
    for l in $xzlevels ; do
      for t in $threads ; do
        sudo purge
        logBegin
        xz -T $t -${l} ${img}.tar
        logEnd "compress-xz" $i size ${img}.tar.xz level $l threads $t
        sudo purge
        logBegin
        xz -T $t --decompress ${img}.tar.xz
        logEnd "decompress-xz" $i level $l threads $t
      done
    done

    for l in $levels ; do
      # Bzip2
      rm -f ${img}.tar.bz2
      sudo purge
      logBegin
      bzip2 -$l ${img}.tar
      logEnd "compress-bzip2" $i size ${img}.tar.bz2 level $l
      sudo purge
      logBegin
      bunzip2 ${img}.tar.bz2
      logEnd "decompress-bzip2" $i level $l

      # Gzip
      rm -f ${img}.tar.gz
      sudo purge
      logBegin
      gzip -$l ${img}.tar
      logEnd "compress-gzip" $i size ${img}.tar.gz level $l
      sudo purge
      logBegin
      gunzip ${img}.tar.gz
      logEnd "decompress-gzip" $i level $l

      # pigz
      for t in $threads ; do
        rm -f ${img}.tar.gz
        sudo purge
        logBegin
        pigz -p ${t} -${l} ${img}.tar
        logEnd "compress-pigz" $i size ${img}.tar.gz level $l threads $t
        sudo purge
        logBegin
        unpigz -p ${t} ${img}.tar.gz
        logEnd "decompress-pigz" $i level $l threads $t
      done
    done
  done
done