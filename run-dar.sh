#!/bin/bash
rm -f results-dar.txt
date > results-dar.txt
./benchmark-dar.sh 2>&1 | tee -a output.txt
cat output.txt | mail -s RESULT -A results-dar.txt $EMAIL
