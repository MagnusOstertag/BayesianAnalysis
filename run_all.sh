#!/bin/bash
####################################
#
# Running all the scripts on all the configs
#
####################################

printf -v date '%(%Y-%m-%d %H:%M)T\n' -1 

Rscript train.R -c input_classification_all.yml -o results -f FALSE >> "logfile.$date.log"
Rscript train.R -c input_classification_few.yml -o results -f FALSE >> "logfile.$date.log"
Rscript train.R -c input_regression_all.yml -o results -f FALSE >> "logfile.$date.log"
Rscript train.R -c input_regression_few.yml -o results -f FALSE >> "logfile.$date.log"

Rscript evaluation.R -t dataset/2022_08_30/ -o results >> "logfile.$date.log"
# Rscript evaluation.R -c input_regression_few.yml -o results >> "logfile.$date.log"
# Rscript evaluation.R -c input_classification_all.yml -o results >> "logfile.$date.log"
# Rscript evaluation.R -c input_classification_few.yml -o results >> "logfile.$date.log"
