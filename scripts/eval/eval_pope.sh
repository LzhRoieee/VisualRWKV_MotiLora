#!/bin/bash
# 
gpu_list="${CUDA_VISIBLE_DEVICES:-0}"
IFS=',' read -ra GPULIST <<< "$gpu_list"

model_path=$1
ctx_len=$2
proj_type=$3
n_embd=$4
n_layer=$5
eval_dir=$6
vision_tower_dir=$7
# image_position=$8
# 使用dirname命令获取父目录的路径
parent_dir=$(dirname "${model_path}")
# get the name of the model without extension
model_name=$(basename "${model_path}")
model_name="${model_name%.*}"
# 切换到脚本所在目录的上两级目录
cd "$(dirname "$(dirname "$0")")/.."

# 打印当前工作目录
echo "Current working directory: $(pwd)"

# 使用basename命令获取父目录名称
exp_name=$(basename "${parent_dir}")
# add model name to exp name
exp_name="${exp_name}_${model_name}"
echo "exp name: $exp_name, model path: $model_path"
echo "ctx_len: $ctx_len, proj_type: $proj_type, n_embd: $n_embd, n_layer: $n_layer"
echo "eval dir: $eval_dir"
echo "vision_tower_dir: $vision_tower_dir"
# "image_position: $image_position"

mkdir -p $eval_dir/eval/pope/answers/$exp_name
CHUNKS=${#GPULIST[@]}
for IDX in $(seq 0 $((CHUNKS-1))); do
    CUDA_VISIBLE_DEVICES=${GPULIST[$IDX]}
    python evaluate.py \
        --ctx_len $ctx_len --proj_type $proj_type --n_embd $n_embd --n_layer $n_layer \
        --vision_tower_dir $vision_tower_dir \
        --model_path $model_path \
        --image_folder $eval_dir/eval/pope/val2014 \
        --question_file $eval_dir/eval/pope/llava_pope_test.jsonl \
        --output_file $eval_dir/eval/pope/answers/$exp_name/${CHUNKS}_${IDX}.jsonl \
        # --image_position $image_position \
        --num_chunks $CHUNKS \
        --chunk_idx $IDX &
    echo "Started chunk $IDX"
done
wait

output_file=$eval_dir/eval/pope/answers/${exp_name}/merge.jsonl
> "$output_file"
# 将三个块文件的内容按顺序合并到 final_output.jsonl
for IDX in $(seq 0 $((CHUNKS-1))); do
    cat $eval_dir/eval/pope/answers/${exp_name}/${CHUNKS}_${IDX}.jsonl >> "$output_file"
done

python eval/eval_pope.py \
    --annotation-dir $eval_dir/eval/pope/coco \
    --question-file $eval_dir/eval/pope/llava_pope_test.jsonl \
    --result-file $eval_dir/eval/pope/answers/$exp_name/merge.jsonl
