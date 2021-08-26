#!/usr/bin/env bash

# Copyright 2013  (Author: Daniel Povey)
# Apache 2.0

# This script takes data prepared in a corpus-dependent way
# in data/local/, and converts it into the "canonical" form,
# in various subdirectories of data/, e.g. data/lang, data/train, etc.

. ./path.sh || exit 1;

echo "Preparing train, dev and test data"
srcdir=data/local/data
lmdir=data/local/nist_lm
tmpdir=data/local/lm_tmp
lexicon=data/local/dict/lexicon.txt
train_set=$2
mkdir -p $tmpdir

str1="$1"
str2="ORGI"
result=$(echo $str1 | grep "${str2}")
if [[ "$result" != "" ]] ; then
    train=train-orgi
else
    train=train-new
fi

if [[ "$result" != "" ]] ; then
    for x in ${train} dev ; do
        mkdir -p data/$x
        cp $srcdir/${x}_wav.scp data/$x/wav.scp || exit 1;
        cp $srcdir/$x.text data/$x/text || exit 1;
        cp $srcdir/$x.spk2utt data/$x/spk2utt || exit 1;
        cp $srcdir/$x.utt2spk data/$x/utt2spk || exit 1;
        utils/filter_scp.pl data/$x/spk2utt $srcdir/$x.spk2gender > data/$x/spk2gender || exit 1;
        [ -e $srcdir/${x}.stm ] && cp $srcdir/${x}.stm data/$x/stm
        [ -e $srcdir/${x}.glm ] && cp $srcdir/${x}.glm data/$x/glm
        utils/fix_data_dir.sh data/$x
        utils/validate_data_dir.sh --no-feats data/$x || exit 1
    done
else
#     for x in dev; do
#         mkdir -p data/$x
#         cp $srcdir/${x}_wav.scp data/$x/wav.scp || exit 1;
#         cp $srcdir/$x.text data/$x/text || exit 1;
#         cp $srcdir/$x.spk2utt data/$x/spk2utt || exit 1;
#         cp $srcdir/$x.utt2spk data/$x/utt2spk || exit 1;
#         utils/filter_scp.pl data/$x/spk2utt $srcdir/$x.spk2gender > data/$x/spk2gender || exit 1;
#         [ -e $srcdir/${x}.stm ] && cp $srcdir/${x}.stm data/$x/stm
#         [ -e $srcdir/${x}.glm ] && cp $srcdir/${x}.glm data/$x/glm
#         utils/fix_data_dir.sh data/$x
#         utils/validate_data_dir.sh --no-feats data/$x || exit 1
#     done
    for x in ${train_set} dev-cov; do
        utils/fix_data_dir.sh data/$x
        utils/validate_data_dir.sh --no-feats data/$x || exit 1
    done
fi
