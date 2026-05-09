# 原始需求管理

## TODO:2026-05-09/1 实现在 bash 中利用 curl 命令行工具调用 api 

创建 ai-curl.sh 脚本，放在 bash/ 子目录中。封装 curl 命令行原始调用 AI 模型的
API 用法。

期望支持特性：
- 用 source 读取 ai-curl.env 文件，配置 API 的基本 URL 与 KEY 环境变量，优先级
  - 指定选项 --env /path/to/file
  - 当前目录下 ./ai-curl.env
  - 当前目录下 ./.chatedit/ai-curl.env
  - 用户目录下 ~/.chatedit/ai-curl.env
- 支持可选选项 --url --key --model 指定参数，优先级高于 env 文件
- 位置参数期望输入一个 json 文件，其格式应适配 api 接受的格式
- 如果没有位置参数，支持从 STDIN 读入 json

env 文件也应满足 bash 语法，相当于在调用 curl 之前执行的前置命令，但主要目的主
要是用于配置环境变量，所以 `=` 前后不应有空格，暴露的环境变更命名为：
- `API_URL`
- `API_KEY`
- `API_MODEL`

待发送的 json 文件，一般必填的 `model` 字段，可用 `$API_MODEL` 环境变量指代。
在 curl 发送前需要处理环境环境变量替换。

然后在 testdata/ 子目录增加一个 ai-curl.env 文件，与一些示例 json 文件，能被
ai-curl.sh 脚本使用。

在 bin/ 子目录下创建 ai-curl 软链接至 bash/ai-curl.sh 脚本。

## TODO: 用 perl 实现将 markdown 聊天文件转换为能发给 api 的 JSON 文件
