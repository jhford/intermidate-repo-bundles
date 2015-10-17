#!/bin/bash
rm -f results.txt
date > results.txt
./benchmarks.sh 2>&1 | mail -s RESULT -A results.txt $EMAIL
