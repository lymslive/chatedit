#!/usr/bin/env bash
# ai-curl.sh: 封装 curl 调用 AI 模型 API
# 用法: ai-curl.sh [选项] [json文件]
#       ai-curl.sh [选项] < input.json

set -euo pipefail

# 检查核心依赖
if ! command -v curl &>/dev/null; then
    echo "错误: 未找到 curl，请先安装" >&2
    exit 1
fi
HAS_JQ=0
command -v jq &>/dev/null && HAS_JQ=1

usage() {
    echo "用法: ai-curl [--env file] [--url url] [--key key] [--model model] [-j] [-d] [-s] [--system msg] [json_file]"
    echo "      从 STDIN 读取 JSON: ai-curl [选项] < input.json"
    echo "  -j, --json      输出原始 JSON（默认用 jq 提取聊天内容）"
    echo "  -d, --debug     打印最终 curl 命令到 stderr，并保留临时文件"
    echo "  -s, --simple    将输入视为纯文本，自动拼装为最简 chat JSON（文件名以 .json 结尾时忽略）"
    echo "  --system <msg>  在 chat JSON 中插入 system 消息；以 @ 开头时读取文件内容"
}

# 命令行参数（优先级最高）
OPT_URL=""
OPT_KEY=""
OPT_MODEL=""
OPT_ENV=""
OPT_JSON=0
OPT_DEBUG=0
OPT_SIMPLE=0
OPT_SYSTEM=""
JSON_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --env)        OPT_ENV="$2";    shift 2 ;;
        --url)        OPT_URL="$2";    shift 2 ;;
        --key)        OPT_KEY="$2";    shift 2 ;;
        --model)      OPT_MODEL="$2";  shift 2 ;;
        --json|-j)    OPT_JSON=1;      shift   ;;
        --debug|-d)   OPT_DEBUG=1;     shift   ;;
        --simple|-s)  OPT_SIMPLE=1;    shift   ;;
        --system)     OPT_SYSTEM="$2"; shift 2 ;;
        --help|-h)    usage; exit 0 ;;
        -*) echo "未知选项: $1" >&2; exit 1 ;;
        *)  JSON_FILE="$1"; shift ;;
    esac
done

# 查找 env 文件（按优先级）
find_env_file() {
    local candidates=(
        "$OPT_ENV"
        "./ai-curl.env"
        "./.chatedit/ai-curl.env"
        "$HOME/.chatedit/ai-curl.env"
    )
    for f in "${candidates[@]}"; do
        if [[ -n "$f" && -f "$f" ]]; then
            echo "$f"
            return
        fi
    done
}

# 加载 env 文件（设置 API_URL / API_KEY / API_MODEL）
ENV_FILE="$(find_env_file)"
if [[ -n "$ENV_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
fi

# 命令行选项覆盖 env 文件中的变量
[[ -n "$OPT_URL"   ]] && API_URL="$OPT_URL"
[[ -n "$OPT_KEY"   ]] && API_KEY="$OPT_KEY"
[[ -n "$OPT_MODEL" ]] && API_MODEL="$OPT_MODEL"

# 导出变量，使 envsubst 子进程可见
export API_URL API_KEY API_MODEL

# 验证必要参数
if [[ -z "${API_URL:-}" ]]; then
    echo "错误: 未设置 API URL，请通过 --url 参数或 env 文件中的 API_URL 配置" >&2
    exit 1
fi
if [[ -z "${API_KEY:-}" ]]; then
    echo "错误: 未设置 API KEY，请通过 --key 参数或 env 文件中的 API_KEY 配置" >&2
    exit 1
fi

# 确定 JSON 来源：位置参数文件 / STDIN 写入临时文件
TMP_FILES=()
cleanup() {
    if [[ $OPT_DEBUG -eq 1 && ${#TMP_FILES[@]} -gt 0 ]]; then
        echo "[debug] 保留临时文件: ${TMP_FILES[*]}" >&2
    else
        [[ ${#TMP_FILES[@]} -gt 0 ]] && rm -f "${TMP_FILES[@]}"
    fi
}
trap cleanup EXIT

# 如果文件名以 .json 结尾，忽略 --simple 选项
if [[ -n "$JSON_FILE" && "$JSON_FILE" == *.json ]]; then
    OPT_SIMPLE=0
fi

if [[ -n "$JSON_FILE" ]]; then
    if [[ ! -f "$JSON_FILE" ]]; then
        echo "错误: 文件不存在: $JSON_FILE" >&2
        exit 1
    fi
    DATA_FILE="$JSON_FILE"
elif [[ ! -t 0 ]]; then
    TMP_STDIN="$(mktemp /tmp/ai-curl-XXXXXX.json)"
    TMP_FILES+=("$TMP_STDIN")
    cat > "$TMP_STDIN"
    DATA_FILE="$TMP_STDIN"
else
    echo "错误: 请提供 JSON 文件或通过 STDIN 输入 JSON 数据" >&2
    usage >&2
    exit 1
fi

# --simple 模式：将纯文本内容拼装为最简 chat JSON
# 将文本转义为 JSON 字符串（处理 \ " 换行 回车 制表符）
json_escape() {
    sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | \
    awk 'NR>1{printf "\\n"} {printf "%s", $0} END{printf "\n"}'
}

if [[ $OPT_SIMPLE -eq 1 ]]; then
    # 读取 system 消息内容
    SYSTEM_CONTENT=""
    if [[ -n "$OPT_SYSTEM" ]]; then
        if [[ "$OPT_SYSTEM" == @* ]]; then
            SYS_FILE="${OPT_SYSTEM:1}"
            if [[ ! -f "$SYS_FILE" ]]; then
                echo "错误: system 文件不存在: $SYS_FILE" >&2
                exit 1
            fi
            SYSTEM_CONTENT="$(json_escape < "$SYS_FILE")"
        else
            SYSTEM_CONTENT="$(printf '%s' "$OPT_SYSTEM" | json_escape)"
        fi
    fi

    # 读取用户消息内容（来自文件或临时文件中的 STDIN 内容）
    USER_CONTENT="$(json_escape < "$DATA_FILE")"

    # 拼装 JSON 写入新临时文件
    TMP_SIMPLE="$(mktemp /tmp/ai-curl-XXXXXX.json)"
    TMP_FILES+=("$TMP_SIMPLE")

    {
        printf '{\n  "model": "$API_MODEL",\n  "messages": [\n'
        if [[ -n "$SYSTEM_CONTENT" ]]; then
            printf '    {"role": "system", "content": "%s"},\n' "$SYSTEM_CONTENT"
        fi
        printf '    {"role": "user", "content": "%s"}\n' "$USER_CONTENT"
        printf '  ]\n}\n'
    } > "$TMP_SIMPLE"

    DATA_FILE="$TMP_SIMPLE"

    if [[ $OPT_DEBUG -eq 1 ]]; then
        echo "[debug] simple 模式拼装的 JSON ($DATA_FILE):" >&2
        cat "$DATA_FILE" >&2
    fi
elif [[ -n "$OPT_SYSTEM" ]]; then
    echo "警告: --system 选项在非 --simple 模式下无效，已忽略" >&2
fi

# 若 JSON 文件中含有 $API_* 占位符，用 envsubst 做变量替换
# 只替换 API_URL / API_KEY / API_MODEL，避免误处理 JSON 中其他 $ 字符
if grep -qE '\$\{?API_(URL|KEY|MODEL)\}?' "$DATA_FILE"; then
    TMP_SUBST="$(mktemp /tmp/ai-curl-XXXXXX.json)"
    TMP_FILES+=("$TMP_SUBST")
    envsubst '$API_URL $API_KEY $API_MODEL' < "$DATA_FILE" > "$TMP_SUBST"
    DATA_FILE="$TMP_SUBST"
    if [[ $OPT_DEBUG -eq 1 ]]; then
        echo "[debug] envsubst 替换后的 JSON ($DATA_FILE):" >&2
        cat "$DATA_FILE" >&2
    fi
fi

# 调试模式：打印即将执行的 curl 命令（KEY 脱敏显示）
if [[ $OPT_DEBUG -eq 1 ]]; then
    MASKED_KEY="${API_KEY:0:6}****${API_KEY: -4}"
    echo "[debug] env file : ${ENV_FILE:-(none)}" >&2
    echo "[debug] API_URL  : $API_URL" >&2
    echo "[debug] API_MODEL: ${API_MODEL:-(unset)}" >&2
    echo "[debug] curl cmd :" >&2
    echo "  curl -s -X POST \\" >&2
    echo "    -H 'Content-Type: application/json' \\" >&2
    echo "    -H 'Authorization: Bearer $MASKED_KEY' \\" >&2
    echo "    -d '@$DATA_FILE' \\" >&2
    echo "    '$API_URL'" >&2
fi

# 调用 API，输出保存临时文件，便于调试和后处理
TMP_RESP="$(mktemp /tmp/ai-curl-XXXXXX.json)"
TMP_FILES+=("$TMP_RESP")

curl -s \
    -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d "@$DATA_FILE" \
    "$API_URL" > "$TMP_RESP"

if [[ $OPT_DEBUG -eq 1 ]]; then
    echo "[debug] 响应文件: $TMP_RESP" >&2
fi

# 输出处理：--json 或 jq 未安装时输出原始 JSON，否则提取聊天内容
if [[ $OPT_JSON -eq 1 || $HAS_JQ -eq 0 ]]; then
    cat "$TMP_RESP"
else
    # 兼容两种主流格式：
    #   OpenAI 兼容格式: .choices[].message.content
    #   Anthropic 原生格式: .content[].text
    jq -r '
        if .choices then
            .choices[] | "\(.message.role): \(.message.content)"
        elif .content then
            .role + ": " + (.content | map(.text) | join(""))
        else
            .
        end
    ' "$TMP_RESP"
fi
