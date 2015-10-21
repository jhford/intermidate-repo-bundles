#!/bin/bash
rm -f results-dar.txt
date > results-dar.txt
./benchmarks.sh 2>&1 | mail -s RESULT -A results-dar.txt $EMAIL
