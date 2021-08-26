#!/usr/bin/env bash

# Copyright 2017 Johns Hopkins University (Shinji Watanabe)
#  Apache 2.0  (http://www.apache.org/licenses/LICENSE-2.0)

. ./path.sh || exit 1;
. ./cmd.sh || exit 1;

# general configuration
backend=pytorch
stage=0       # start from -1 if you need to start from data download
stop_stage=100
ngpu=0         # number of gpus ("0" uses cpu, otherwise use gpu)
debugmode=1
dumpdir=dump   # directory to dump full features
N=0            # number of minibatches to be used (mainly for debugging). "0" uses all minibatches.
verbose=1      # verbose option
resume=        # Resume the training from snapshot

# feature configuration
do_delta=false
cmvn=

preprocess_config=conf/specaug.yaml
train_config=
lm_config=

# rnnlm related
skip_lm_training=true   # for only using end-to-end ASR model without LM
lm_resume=              # specify a snapshot file to resume LM training
lmtag=                  # tag for managing LMs
use_lang_model=false
lang_model=
# decoding parameter
p=0.01
recog_model=
recog_dir=exp/retrain-random_${p} # set a model to be used for decoding: 'model.acc.best' or 'model.loss.best'
decode_config=
decode_dir=decode
api=v2

# test related
models=tedlium2.transformer.v1

# model average realted (only for transformer)
# n_average=10                 # the number of ASR models to be averaged
# use_valbest_average=true     # if true, the validation `n_average`-best ASR models will be averaged.
#                              # if false, the last `n_average` ASR models will be averaged.

# bpemode (unigram or bpe)
nbpe=500
bpemode=unigram

# exp tag
tag="" # tag for managing experiments.
recog_set=test-feature-gini-1155

# gini related
orgi_flag=false
orgi_dir=
need_decode=true

. utils/parse_options.sh || exit 1;

# Set bash to 'debug' mode, it will exit on :
# -e 'error', -u 'undefined variable', -o ... 'error in pipeline', -x 'print commands',
set -e
set -u
set -o pipefail

# train_set=train_trim_sp
# train_dev=dev_trim

download_dir=${decode_dir}/download

if [ "${api}" = "v2" ] && [ "${backend}" = "chainer" ]; then
    echo "chainer backend does not support api v2." >&2
    exit 1;
fi

if [ -z $models ]; then
    if [ $use_lang_model = "true" ]; then
        if [[ -z $cmvn || -z $lang_model || -z $recog_model || -z $decode_config ]]; then
            echo 'Error: models or set of cmvn, lang_model, recog_model and decode_config are required.' >&2
            exit 1
        fi
    else
        if [[ -z $cmvn || -z $recog_model || -z $decode_config ]]; then
            echo 'Error: models or set of cmvn, recog_model and decode_config are required.' >&2
            exit 1
        fi
    fi
fi

dir=${download_dir}/${models}
mkdir -p ${dir}


function download_models () {
    if [ -z $models ]; then
        return
    fi

    file_ext="tar.gz"
    case "${models}" in
        "tedlium2.rnn.v1") share_url="https://drive.google.com/open?id=1UqIY6WJMZ4sxNxSugUqp3mrGb3j6h7xe"; api=v1 ;;
        "tedlium2.rnn.v2") share_url="https://drive.google.com/open?id=1cac5Uc09lJrCYfWkLQsF8eapQcxZnYdf"; api=v1 ;;
        "tedlium2.transformer.v1") share_url="https://drive.google.com/open?id=1cVeSOYY1twOfL9Gns7Z3ZDnkrJqNwPow" ;;
        "tedlium3.transformer.v1") share_url="https://drive.google.com/open?id=1zcPglHAKILwVgfACoMWWERiyIquzSYuU" ;;
        "librispeech.transformer.v1") share_url="https://drive.google.com/open?id=1BtQvAnsFvVi-dp_qsaFP7n4A_5cwnlR6" ;;
        "librispeech.transformer.v1.transformerlm.v1") share_url="https://drive.google.com/open?id=17cOOSHHMKI82e1MXj4r2ig8gpGCRmG2p" ;;
        "commonvoice.transformer.v1") share_url="https://drive.google.com/open?id=1tWccl6aYU67kbtkm8jv5H6xayqg1rzjh" ;;
        "csj.transformer.v1") share_url="https://drive.google.com/open?id=120nUQcSsKeY5dpyMWw_kI33ooMRGT2uF" ;;
        *) echo "No such models: ${models}"; exit 1 ;;
    esac

    if [ ! -e ${dir}/.complete ]; then
        download_from_google_drive.sh ${share_url} ${dir} ${file_ext}
        touch ${dir}/.complete
    fi
}

# Download trained models
if [ -z "${cmvn}" ]; then
    #download_models
    cmvn=$(find ${download_dir}/${models} -name "cmvn.ark" | head -n 1)
fi
if [ -z "${lang_model}" ] && ${use_lang_model}; then
    #download_models
    lang_model=$(find ${download_dir}/${models} -name "rnnlm*.best*" | head -n 1)
fi
if [ -z "${recog_model}" ]; then
    #download_models
    if [ -z "${recog_dir}" ]; then
        recog_model=$(find ${download_dir}/${models} -name "model*.best*" | head -n 1)
    else
        recog_model=$(find "${recog_dir}/results" -name "model.acc.best" | head -n 1)
    fi
    echo "recog_model is ${recog_model}"
fi
if [ -z "${decode_config}" ]; then
    #download_models
    decode_config=$(find ${download_dir}/${models} -name "decode*.yaml" | head -n 1)
fi
# if [ -z "${wav}" ]; then
#     #download_models
#     wav=$(find ${download_dir}/${models} -name "*.wav" | head -n 1)
# fi

# Check file existence
if [ ! -f "${cmvn}" ]; then
    echo "No such CMVN file: ${cmvn}"
    exit 1
fi
if [ ! -f "${lang_model}" ] && ${use_lang_model}; then
    echo "No such language model: ${lang_model}"
    exit 1
fi
if [ ! -f "${recog_model}" ]; then
    echo "No such E2E model: ${recog_model}"
    exit 1
fi
if [ ! -f "${decode_config}" ]; then
    echo "No such config file: ${decode_config}"
    exit 1
fi
# if [ ! -f "${wav}" ]; then
#     echo "No such WAV file: ${wav}"
#     exit 1
# fi


# if [ ${stage} -le -1 ] && [ ${stop_stage} -ge -1 ]; then
#     echo "stage -1: Data Download"
#     local/download_data.sh
# fi
echo "stage ${stage}"

if [ ${stage} -le 0 ] && [ ${stop_stage} -ge 0 ]; then
    ### Task dependent. You have to make data the following preparation part by yourself.
    ### But you can utilize Kaldi recipes in most cases
    echo "stage 0: Data preparation"
    if [ -z "${recog_dir}" ]; then 
        local/prepare_test_data.sh ${recog_set}
    fi
    for dset in ${recog_set}; do
        utils/fix_data_dir.sh data/${dset}.orig
        utils/data/modify_speaker_info.sh --seconds-per-spk-max 180 data/${dset}.orig data/${dset}
    done
fi

# feat_tr_dir=${dumpdir}/${train_set}/delta${do_delta}; mkdir -p ${feat_tr_dir}
# feat_dt_dir=${dumpdir}/${train_dev}/delta${do_delta}; mkdir -p ${feat_dt_dir}
if [ ${stage} -le 1 ] && [ ${stop_stage} -ge 1 ]; then
    ### Task dependent. You have to design training and dev sets by yourself.
    ### But you can utilize Kaldi recipes in most cases
    echo "stage 1: Feature Generation"
    fbankdir=fbank
    
    # Generate the fbank features; by default 80-dimensional fbanks with pitch on each frame
    for x in ${recog_set}; do
        #utils/fix_data_dir.sh data/${x}
        steps/make_fbank_pitch.sh --cmd "$train_cmd" --nj 32 --write_utt2num_frames true \
            data/${x} exp/make_fbank/${x} ${fbankdir}
        utils/fix_data_dir.sh data/${x}
    done

#     remove utt having > 2000 frames or < 10 frames or
#     remove utt having > 400 characters or 0 characters
#     remove_longshortdata.sh --maxchars 400 data/train data/train_trim
#     remove_longshortdata.sh --maxchars 400 data/dev data/${train_dev}

    # speed-perturbed
#     utils/perturb_data_dir_speed.sh 0.9 data/train_trim data/temp1
#     utils/perturb_data_dir_speed.sh 1.0 data/train_trim data/temp2
#     utils/perturb_data_dir_speed.sh 1.1 data/train_trim data/temp3
#     utils/combine_data.sh --extra-files utt2uniq data/${train_set} data/temp1 data/temp2 data/temp3
#     rm -r data/temp1 data/temp2 data/temp3
#     steps/make_fbank_pitch.sh --cmd "$train_cmd" --nj 32 --write_utt2num_frames true \
#         data/${train_set} exp/make_fbank/${train_set} ${fbankdir}
#     utils/fix_data_dir.sh data/${train_set}

    # compute global CMVN
#     compute-cmvn-stats scp:data/${train_set}/feats.scp data/${train_set}/cmvn.ark

    # dump features for training
#     feat_tr_dir=${dumpdir}/${train_set}/delta${do_delta}; mkdir -p ${feat_tr_dir}
#     dump.sh --cmd "$train_cmd" --nj 32 --do_delta ${do_delta} \
#         data/${train_set}/feats.scp ${cmvn} exp/dump_feats/train ${feat_tr_dir}
#     dump.sh --cmd "$train_cmd" --nj 32 --do_delta ${do_delta} \
#         data/${train_dev}/feats.scp data/${train_set}/cmvn.ark exp/dump_feats/dev ${feat_dt_dir}
    for rtask in ${recog_set}; do
        feat_recog_dir=${dumpdir}/${rtask}/delta${do_delta}; mkdir -p ${feat_recog_dir}
        dump.sh --cmd "$train_cmd" --nj 32 --do_delta ${do_delta} \
            data/${rtask}/feats.scp ${cmvn} exp/dump_feats/recog/${rtask} \
            ${feat_recog_dir}
    done
fi

dict=data/lang_char/train_trim_sp_${bpemode}${nbpe}_units.txt
bpemodel=data/lang_char/train_trim_sp_${bpemode}${nbpe}
if [ ${stage} -le 2 ] && [ ${stop_stage} -ge 2 ]; then
    ### Task dependent. You have to check non-linguistic symbols used in the corpus.
    echo "stage 2: Dictionary and Json Data Preparation"
#     mkdir -p ${decode_dir}/${models}
#     dict=${decode_dir}/${models}/dict
#     load_dict.py \
#     --modeljson "${download_dir}/${models}/exp/train_rnnlm_pytorch_lm_irie_batchsize128_unigram500/model.json" \
#     --dict ${dict}
#     bpemodel=${decode_dir}/${models}/${train_set}_${bpemode}${nbpe}
#     mkdir -p data/lang_char/
#     echo "<unk> 1" > ${dict} # <unk> must be 1, 0 will be used for "blank" in CTC
#     cut -f 2- -d" " data/${train_set}/text > data/lang_char/input.txt
#     spm_train --input=data/lang_char/input.txt --vocab_size=${nbpe} --model_type=${bpemode} \
#         --model_prefix=${bpemodel} --input_sentence_size=100000000
#     spm_encode --model=${bpemodel}.model --output_format=piece < data/lang_char/input.txt | \
#         tr ' ' '\n' | sort | uniq | awk '{print $0 " " NR+1}' >> ${dict}
#     wc -l ${dict}

    # make json labels
#     data2json.sh --feat ${feat_tr_dir}/feats.scp --bpecode ${bpemodel}.model \
#          data/${train_set} ${dict} > ${feat_tr_dir}/data_${bpemode}${nbpe}.json
#     data2json.sh --feat ${feat_dt_dir}/feats.scp --bpecode ${bpemodel}.model \
#          data/${train_dev} ${dict} > ${feat_dt_dir}/data_${bpemode}${nbpe}.json

    for rtask in ${recog_set}; do
        feat_recog_dir=${dumpdir}/${rtask}/delta${do_delta}
        data2json.sh --feat ${feat_recog_dir}/feats.scp --bpecode ${bpemodel}.model\
            data/${rtask} ${dict} > ${feat_recog_dir}/data_${bpemode}${nbpe}.json
    done
fi

if [ -z "${recog_dir}" ]; then
    expname=${models}
    expdir=exp/${expname}
    mkdir -p ${expdir}
else
    expdir=${recog_dir}
fi


if [ ${stage} -le 3 ] && [ ${stop_stage} -ge 3 ]; then
    echo "stage 3: Decoding"
    nj=32
    if ${use_lang_model}; then
        recog_opts="--rnnlm ${lang_model}"
    else
        recog_opts=""
    fi
    #feat_recog_dir=${decode_dir}/dump
    pids=() # initialize pids
    #trap 'rm -rf data/"${recog_set}" data/"${recog_set}.orig"' EXIT
    for rtask in ${recog_set}; do
    (
        decode_dir=decode_${rtask}_decode_${lmtag}
        feat_recog_dir=${dumpdir}/${rtask}/delta${do_delta}

#         # split data
        if "${need_decode}"; then
            splitjson.py --parts ${nj} ${feat_recog_dir}/data_${bpemode}${nbpe}.json
        fi
        orgi_dir=${expdir}/decode_test-orgi_decode_${lmtag}
        
        #### use CPU for decoding
        ngpu=0
        if "${need_decode}"; then
#             ${decode_cmd} JOB=1:${nj} ${expdir}/${decode_dir}/log/decode.JOB.log \
            asr_test.py \
            --config ${decode_config} \
            --ngpu ${ngpu} \
            --backend ${backend} \
            --debugmode ${debugmode} \
            --verbose ${verbose} \
            --recog-json ${feat_recog_dir}/split32utt/data_${bpemode}${nbpe}.24.json \
            --result-label ${expdir}/${decode_dir}/data.24.json \
            --model ${recog_model}  \
            --api ${api} \
            --orgi_dir ${orgi_dir} \
            --need_decode ${need_decode} \
            --orgi_flag ${orgi_flag} \
            --recog_set ${recog_set} \
            ${recog_opts}
            
        else
            asr_test.py \
            --config ${decode_config} \
            --ngpu ${ngpu} \
            --backend ${backend} \
            --debugmode ${debugmode} \
            --verbose ${verbose} \
            --recog-json ${feat_recog_dir}/split${nj}utt/data_${bpemode}${nbpe}.JOB.json \
            --result-label ${expdir}/${decode_dir}/data.JOB.json \
            --model ${recog_model}  \
            --api ${api} \
            --orgi_dir ${orgi_dir} \
            --need_decode ${need_decode} \
            --orgi_flag ${orgi_flag} \
            --recog_set ${recog_set} \
            ${recog_opts}           
        fi

    ) &
    pids+=($!) # store background pids
    done
    i=0; for pid in "${pids[@]}"; do wait ${pid} || ((++i)); done
    [ ${i} -gt 0 ] && echo "$0: ${i} background jobs are failed." && false

fi


if [ ${stage} -le 4 ] && [ ${stop_stage} -ge 4 ]; then
    echo "stage 4: Scoring"
    decode_dir=decode_${recog_set}_decode_${lmtag}
    if "${need_decode}"; then
       score_sclite.sh --bpe ${nbpe} --bpemodel ${bpemodel}.model --wer true --need_decode ${need_decode} --guide_type "random" ${expdir}/${decode_dir} ${dict}
    else
       score_sclite.sh --bpe ${nbpe} --bpemodel ${bpemodel}.model --wer true --need_decode ${need_decode} --guide_type "gini" ${expdir}/${decode_dir} ${dict}
       score_sclite.sh --bpe ${nbpe} --bpemodel ${bpemodel}.model --wer true --need_decode ${need_decode} --guide_type "cov" ${expdir}/${decode_dir} ${dict}
       score_sclite.sh --bpe ${nbpe} --bpemodel ${bpemodel}.model --wer true --need_decode ${need_decode} --guide_type "random" ${expdir}/${decode_dir} ${dict}
    fi
    echo "Finished"
fi
           
    