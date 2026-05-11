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

### DONE:20260509-121506

## TODO:2026-05-09/2 优化 ai-curl 在单次聊天的内容输入用法

现在 ai-curl.sh 脚本只支持发送完整合法的 json 。
假设只想做单轮简单聊天，希望支持快捷输入无格式内容。

增加一个选项 --simple|-s ，将标准输入或位置参数的文件当作普通文本文件，
然后按 testdata/chat-simple.json 格式拼装最简 json 。

为保证 json 拼装正确，至少要处理输入文本转义引号与回车换行符，
但不必处理复杂的 utf-8 中文转义。
有什么常用的 linux 命令行工具可处理这项工作?
ai-curl bash 脚本希望尽量保持依赖简单。

如果参数文件名以 `.json` 结束，则忽略 -s 选项，仍认为输入是完整 json 。

最终希望支持如下用法：
```bash
echo "Hello, who are you?" | bin/ai-curl --simple
```

另外，希望扩展支持 --system 选项，在拼装 json 时额外插入一条 system 消息。
如果 --system 参数值以 `@` 开头，认为后续是一个文本文件。否则允许将不长的一句
话直接写在命令行中。

按此前设计，拼装的 json 先写临时文件，以便支持原来的环境变量替换。

请评估只用 bash 实现该功能的复杂性与可行性。

### DONE:20260509-160151

## TODO:2026-05-11/1 用 perl 实现将 markdown 聊天文件转换为能发给 api 的 JSON 文件

新建 perl/ai-chat.pl 脚本，根据 `docs/chat-format.md` 文档描叙的格式解析文档，
转为适合发往大模型 API 的 json 内容。

文档主要提供对话内容，调用 API 所需的其他参数写在 json 模板文件中。
模板文件优先级：
- 支持 `--template|-t` 选项指定一个 json 模板文件
- 当前目录 `./ai-chat.json`
- 当前目录 ./.chatedit/ai-chat.json
- 用户目录 ~/.chatedit/ai-chat.json
- 内联固定模板类似 `testdata/chat-simple.json`

模板文件可以省略 `messages` 或留个空数组，即使用非空 `messages` 也被文档解析内
容替换。建议将 `messages` 空数组写在最后。

实施要求，尽可能低依赖，只使用系统安装的 perl 5 自带模块，不额外从 cpan 下载第
三方扩展模块。可以当前开发环境的 perl 安装情况为参考。

输入内容如 `input.md` 文件名可放在命令行参数中，也可通过标准输入。
目前可限定只允许一个输入文件，忽略多余文件。没有输入文件时，读取标准输入。

输出 json 打印到标准输出。故脚本中若有任何调试或警告错误信息打印出标准错误。
可以支持 `--debug|-d` 选项开启打印更详细的有助于调试问题的信息。

这个脚本初步功能完成后，应该可以联用 `ai-curl.sh` 调用 API 。例如：

cat docs/chat-format.md | perl/ai-chat.pl | bash/ai-curl.sh

并且在 `testdata/` 子目录中也增加一两个 `.md` 示例文件。原来的 `.json` 示例文
件应该能充当模板文件。

perl 脚本实现开启 strict 模式，不要炫技晦涩，要求易读可维护。编写 pod 内嵌文档，
其他注释保持简明。
### DONE: 20260511-165415
