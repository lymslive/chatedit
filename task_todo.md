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

## TODO:2026-05-11/2 优化 ai-chat.pl 外部引入错误处理

外部引入内容 `@` 与 `!` 的规则改为只允许在有效二级对话段 `## role >>` 中出现。
此前规则声明在 `# ` 注释段就地扩展包含可能涉及递归引入，实现复杂而实用不高，性
价比不高。

此外，增加规定错误处理。
如果 `@` 或 `!` 出错，输出原文本行，再于行尾隔一空格加上错误标记：
- 读取 `@` 文件失败或运行 `!` 命令失败，加 `(Read Error)` 后缀
- 当 `@` 或 `!` 无输出或仅空白输出时，加 `(Read Empty)` 后缀

同步更新 `ai-char.pl` 脚本内的相关注释与文档。

另外，也再检查一下 `## role >>` 段下是否支持 `###` 等次级子标题，它不应该结束
当前段。因为 `###` 也匹配 `/^##/` 与 `/^#/` ，我怀疑在 `sub parse_chat` 中会
提前结束当前行循环。

docs/chat-format.md 可随本次任务一起提交，上个任务漏提交了。

### DONE: 20260511-215428

## TODO:2026-05-12/1 扩展 ai-chat.pl 集成 ai-curl 实际发送功能

当前这两个脚本必须管理联用，如 
cat input.md | perl/ai-chat.pl | bash/ai-curl.sh

现想将发送功能集成到一个脚本，两个目的：
- 提升效率，原 ai-curl.sh 脚本调用很多工具，开启多个进程
- 支持原位修改输入的聊天文件.md，附在末尾，然后重复调用达到多轮聊天效果

期望的功能流程：
- 读取 md 文档
- 结合模板拼装 json
- 请求 https API
- 解析 API 响应的 json，回写 md 文档

扩充的命令行选项及相关功能：
- 支持 ai-curl.sh 的 --env --url --key --model --system 选项，逻辑类似；
- 模板 json 的 model 字段检查替换 `$API_MODEL` 环境变量；
- 扩展 --system 功能，命令行未指定该选项时，可依次按优先级读取
  (. | ./.charedit | ~/.charedit)/ai-chat.sys 文件，
  可以用 `--system ""` 空参数或不带参数时抑止查找文件，
  非空参数时将内容插入 messages 第一个元素，role = system
- 支持 `-i` 选项(长选项名该用哪个单词？)表示原位修改输入的 `.md` 文件，
  否则只将 API 回复内容打印至标准输出；
  如果从标准输入无文件可修改，则先复制原输入到标准输出；
- 支持无参选项 `--header` 表示打印额外的 `## role >>` 二级标题，回复的 role 一
  般是 `assistant`；`-i` 隐含 `--header` ，并且输入文件最后一行不是空行时额外
  加一空行，以便与原内容有分隔感；
- 支持 `--encode` 选项跳过请求 API 请求及后续流程，相当于当前 `ai-chat.pl` 功
  能，只打印组装的 json 内容至标准输出，忽略 `-i` 选项；此时以 pretty 格式打印
  json 结果可用于观察调试，而正常流程要发送至 API 时，按压缩单行的 json 发送，
  减少消耗；
- 支持逆向操作的 `--decode` 选项，输入 json ，输出 mardown （仅有对话段二级标
  题系列）

最终应该支持的功能用法：
```bash
# --encode 降级兼容，保持与 ai-curl.sh 原始脚本的管道联用
cat input.md | perl/ai-chat.pl --encode | bash/ai-curl.sh

# --decode/--encode 互逆操作互相测验
cat input.md | perl/ai-chat.pl --encode | perl/ai-chat.pl --decode

# 原位修改下的多轮对话迭代
perl/ai-chat.pl -i chat.md
# 追加问题后再执行
perl/ai-chat.pl -i chat.md
...
```

关于执行 https 请求 API 的技术选型，我有几个备选想法：
- 仍然调用 curl 工具，捕获输出，除 perl 解释器，curl 应该是唯一的额外进程，其
  他字符串操作用 perl 完成；
- 保持最低依赖，perl5 自带模块能否实现 https 请求
- 从 cpan 额外安装最常用的 https 请求模块
- 调查有没现成的开源模块已封装 openai 的 API 请求模块

先采用第一种最简单的调用 curl 工具实现一个可用版本。其他几种方案的评估先写到
`doing_plan.tmp/` 子目录的文档中，留作后续参考。

调用 API 的错误处理，如果返回 json 包含错误，无法提取对话内容，则将返回的原始
json 打印标准错误，忽略 `-i`；此前的其他任何错误也直接打印标准错误提前终止。

### DONE: 20260512-122319

## TODO:2026-05-12/2 补充文档

至此已用 perl 脚本实现了基本功能。
请根据当前已实现功能，以及参考 `task_todo.md` 与 `task_log.md` 任务文档，
完善项目 readme 文档，以及 claude 文档。

另请确认 claude 是否也能自动读取 AGENTS.md 文档，考虑到项目可能也用其他工具辅助
开发，最好命名为通用文件名。

### DONE: 20260512~173130

## TODO:2026-05-12/3 模型回复中文时仍然偶发乱码

测试现象：

perl/ai-chat.pl -t testdata/kimi-nothink.json testdata/chat-system.md
正常显示中文

perl/ai-chat.pl -t testdata/kimi-nothink.json docs/chat-format.md
出现乱码

perl/ai-chat.pl -t testdata/kimi-nothink.json docs/chat-format.md --encode | bash/ai-curl.sh
正常显示中文

请分析可能的原因。

另外我有疑问，为什么在实现中要专门开启 utf8 模式处理输入输出。
我想简单处理的话，就将一个汉字当成 3 个字节流好了。
没有在内部处理每个独立汉字的需求，只要在输出终端时能正常显示就好。
避免 utf8 编解码，也能提升性能。

如果这样简化处理，会有什么其他问题吗？

### DONE: 20260512-183920

## TODO:2026-05-13/1 完善 perl 脚本实现的单元测试

为 perl/ai-chat.pl 设计自动化单元测试。
应符合 perl 社区测试规范。如果需要安装依赖模块，请先告知于我。

测试代码也放在 perl 子目录。

请求真实 API 可能较费时，单元测试如何模拟 api 响应？

### DONE: 20260513-122409

## TODO:2026-05-13/2 自动查找辅助配置文件功能优化

ai-chat.pl 与 ai-curl.sh 涉及自动查几种配置文件，当前是查固定文件名。
想改为随程序脚本名变化，即 `$0` 。

查找目录的优先级不变，仍是 ./ ./.chatedit/ ~/.chatedit/

用意是允许用户为脚本创建软链接如 kimi-chat 至 ai-char.pl ，
然后它就自动查找 kimi-chat.env kimi-chat.json kimi-chat.sys 等。
最后仍支持回滚兼容查找通用的 ai-chat.env 等文件。

目前 ai-chat.pl 查的是 ai-curl.env ，按此逻辑纠正为查 ai-chat.env

注意如果不是直接执行脚本，而是通过解释器启动时，
如 bash ai-curl.sh 或 perl ai-chat.pl
脚本名仍能用 `$0` 正确获取吗？

### DONE: 20260513-145043

## TODO:2026-05-13/3 ai-chat.pl 功能扩展 -j -s --postdir

之前 ai-curl.sh 支持的 --json 与 --simple 也集成到 ai-chat.pl

当指定 --simple(-s) 选项时，将整个输入当成简单一段 user 问话，而不必解析为
mardown 文档。

当指定 --json 时，不必再解析 API 响应信息，直接打印原 json 至标准输出，且忽略
-i 原位修改选项。

此外，如果 --postdir 指定了一个有效目录（例如 `post.tmp/`），则将发送给 API 的
json 内容保存至该目录，用 `程序名-yyyymmdd-hhmmss.json` 命名。程序名即
`ai-chat` ，但可能被改名或软链接为其他名字。指定目录不存在时，不主动新建目录，
但可打印一条调试告警信息。此选项的用途在于不想用 `--debug` 打印太多冗余信息时
仍可保存最终发送的 json 内容，以备后续可能的排查之需。

需要补充单元测试用例覆盖新功能。

另外，再检查上次任务修改的配置文件查找顺序功能，似乎也没有覆盖单元测试。
与配置文件相关的测试用例文件可以放在 testdata/ 目录（及其子目录）中，也可以放
脚本的软链接改名。

testdata/ 目录可提交版本库，与测试用例同步。`.chatedit` 目录不提交，用于手动真
实请求 API 的测试验证。

### DONE: 20260513-154929

## TODO:2026-05-14/1 ai-chat.pl 支持流式响应与解析

可以两种方式开启流式响应：
- 命令行选项 --stream
- json 模板中明确写入 `"stream":true`

主流 AI 平台都是用这个字段表示流式响应吗？
还是说直接从响应判断是否流式响应更靠谱。

是否会与原位修改文件的 `-i` 选项冲突？
流式响应先实时打印到标准输出。如果也开启了 `-i` 再追加到原文件。

流式应该不会与 `-json` 冲突，直接打印原 json 流到标准输出。

### DONE: 20260514-121333

## TODO:2026-05-16/1 增加 fix-level 选项修在回复的标题等级

我发现 AI 模型的回复 markdown 格式时经常用二级标题划分内容。

在开启 -i 原位修改选项写回聊天文件时，再发起多轮对话时，那些二级标题就会干扰消
息组编码。即使加上 `testdata/system-markdown.txt` 系统提示词也不能避免，依然会
有强大的惯性输出二级标题。

所以增加一个 `--fix-level` 选项，取值 0 或 1 ，表示是否增加回复内容的标题等级。
将回复的二级及以上标题等级增加一个等级，至少三级标题，即 `###` 开头。

很少看到有回复一级标题的，但如遇到，就增加两级标题，也修改为三级标题。

修改标题的默认行为：
- 打印标准输出时，fix-level=0，尽量保持原回复信息
- 写回原文件时，fix-level=1，以满足多轮对话编码格式

显式的 `--fix-level` 选项可同时覆盖写标准输出与写文件的行为。

### DONE: 20260516-102547

## TODO:2026-05-16/2 api-chat.pl 交互逻辑重构优化

作为可在终端命令行运行的聊天工具，输出时应该有两阶段的打印：
- 先打印到标准输出 stdout
- 根据选项 `-i` 回写到原文件，默认无回写阶段

现在有个问题是，当未开启 --stream 选项时，没有打印 stdout 的阶段一。

--stream 不仅为缓解用户焦虑，能在终端上及时有输出，也可能在技术上避免整体回复
太慢导致 curl 网络请求超时。所以 --stream 与是否打印到终端没有强联系，不管是否
流式都应该先打印到终端。

那有没只回写文件而不打印终端的需求呢？我觉得为保持实现简洁，先不必考虑增加该功
能选项，当用户真有这种需求时，重定向 `>/dev/null` 可解决。

回写聊天文件，是为了能多轮对话，所以需要满足一定的格式。当前 `--header` 与
`--fix-level` 都为了解决这个问题。故可合并为一个重新格式化选项 `--reformat` ，
取值逻辑与当前 `--fix-level` 相同 0 或 1。打印终端时默认不需要重格式化，回写文
件时默认需要。

然后回写文件的选项名，改用 `--append|-a` 比 `--inplace` 更合适，它只会在文件末
尾追加，而不会中间修改。

当从标准输入 stdin 时，没有原文件实体，回写的行为是先将原 stdin 拷到 stdout ，
将 stdout 当成一个特殊的原文件来回写。于是在这种情况下，两阶段的打印合并为一个
了，按第二阶段回写文件处理，即默认需要重格式化。只是仅标准输入但没有
`--append` 选项时，仍按原逻辑，只按第一阶段打印 stdout 。

选项 `--simple` 单轮对话模式，虽常与 stdin 一起出现，但两者是相互独立的。即使
从文件读取也可以是 `--simple`，所以该选项只表示输出的格式，逻辑不变。

再加一个功能，当需要回写文件时，完成回写后，在标准错误打印一行特殊注释，`# <!
-- %d lines appended to file: %s; reformated lines: %d -->` 但当没有原文件从
stdin 输入时不需要打印该提示。

优化一下主函数流程，`is_stream` 那段有点怪味。从总体交互框架看，流式与否不是最
关键的区别。如果实现上确实有较大区别，最次也该在主函数中分发两种运行模式，拆出
两个子函数，同时尽量避免重复代码。

在 stdin 与 --append 同时开启时，可以在网络请求之前就先把 stdin 拷到 stdout 这
个特殊文件准备好，等到回复再 append 剩下内容。

记得同步更新单元测试与文档。

### DONE: 20260516-154114

## TODO:2026-05-16/3 api-chat.pl 代码风格重构优化

我希望每个 sub 函数的大括号从下行行首开始，以便在 vim 中浏览代码时可以用快捷键
`[[` 与 `]]` 定位前一个、后一个函数。

其他风格可保持不变。将代码风格总结后写入 claude 等 agent 能自动读取的文件。但
考虑本仓库可能采用多语言开发，perl 代码风格文件应写 perl/ 子目录中。

然后我 review 代码后有一些改进意见，请评估修改。

`open_input` 额外返回 `$stdin_buffer` 有点怪，且在主函数跨越多行才用到。建议：
- 只返回一个文件句柄
- 再拆出一个 `open_stdin` 专门处理 stdin 特殊逻辑，由 `open_input` 调用
- 减少反复打开关闭文件句柄次数，尽量在一个循环中从 stdin 读取内容写入临时文件
  与 stdout (--append 开启时)
- 当 `--encode` 开启时，`--apend` 应无效，先处理该选项抑制逻辑，再调用
  `open_input` 

请求 API 的 json 内容不要重复写临时文件：
- 先调用 `save_to_postdir`
- 保存失败时再创建临时文件
- 将文件名传给 `run_stream` 或 `run_non_stream`

仅 `call_api` 函数有写 "[debug] curl: POST" 调试日志，`call_api_stream` 没写，
这个动作可以提到主函数分发调用之前。

查找三个辅助配置文件的逻辑类似，仅查找后缀名(env sys json)不同，
可重构提取为同一个函数，以后缀名为参数。
命令行选项抑止查找逻辑也类似，`--system` 与 `--env` 或 `--template` 地位相当，
似乎没必要额外加个 `$opt_system_given` 特殊对待吧。
只要提供了命令行选项，就没有查找文件过程。
考虑这三个选项对就的变量默认值改为空值 undef ，传零值（0或""）都跳过查找过程。

适当精简显而易或过时的注释。

### DONE: 20260516-180109

## TODO:2026-05-18/1 ai-chat.pl 查找配置文件及读取全文件优化

三种配置文件及关联的命令行选项：
- 环境变量.env --env
- 系统提示词.sys --system
- 请求模板.json --template

行为逻辑相似，以 `env` 为例，生效顺序（优先级）重申如下：
- 命令行选项 --env
- 查找同程序名 ./prog.env ./.chatedit/prog.env ~/.chatedit/prog.env
- 查找通用名 ./ai-chat.env ./.chatedit/ai-chat.env ~/.chatedit/ai-chat.env

当前 `find_config_file` 查找顺序不完全准确，在第二级与第三级之间有交叉。
返回有效配置文件前打印 --debug 信息。

只要指定了 --env 选项，就不该再查找 `.env` 配置文件。
- 如果指定的文件读取失败，stderr 打印警告
- 特例如果指定参数（文件名）是零值即空字符串 `""` 或 `0`，不需警告，特地用于抑
  止文件自动查机制，在 --debug 时可以打印调试提示信息

可能理论上虽不能用空字符串作文件名，但可能可以 `0` 做文件名，但实践上机乎不会
出现，用户一定要用 `0` 命名文件由用户自行负责。在 perl 中，空串与 `0`都是当作
false 吧。

所以 `find_config_file` 只要接收一个参数，不要把选项值传进来。
有选项时根本就不该调用该函数。

只有一点区别，`--system` 允许将简单一句话直接写在命令行，才需要用 `@` 区分引导
文件名。环境变量与模板文件都是有格式要求的，直接写在命令行中不适用，只认为传文
件名。从这个角度理解，将 `--system ""`当作直接的内容参数，也就没插入任何系统
提示词，而 `--system 0` 仅注入一个 `0` 提示也几乎没有意义，所以可提前忽略。

代码中有多处将文件内容全部读到一个字符串的功能，例如：
- 读取 system 提示文件
- 读取 template 模板文件
- decode 模式下读取输入文件
- simple 模式下读取输入文件

可以提取一个 `read_file_content` 函数统一封装一下，并去除首尾的空白包括回车。
检查所有需要读取全文的情况，尽量复用调用该函数。
逐行读取文件的情况可不改。

在 --decode 模式时，没必要读取环境变量，故而移到 `load_env` 之前。
且可以精简合并 `open_file_or_stdin` 与 `decode_to_md` 两个函数。

测试文件 `8-find-env.t` 改为 `8-find-config.t` ，适当补充查询另外两种配置文件
查找与选项的测试。

测试文件 `10-fix-level.t` 改名为 `10-reformat` ，因为最初设计的 `--fix-level`
选项也合并为 `--reformat` 了。

### DONE: 20260518-151541

## TODO:2026-05-19/1 ai-chat.pl 代码 review 及优化

review 报告见 `doing_plan.tmp/code-review-perl.md` 。
所有意见比较中肯，可以参照执行，用最直观的方式修改代码。

其中 B2 ，如果流式输出的角色名实时提取复杂，预先打印固定 `assistant` 也勉强能
接受，但要注释说明。但最好能与非流式的行为统一，延后根据实际输出打印 role，默
认值可用 `assistant` 。

### DONE: 20260519-143141

## TODO:2026-05-19/2 ai-chat.pl 补充单元测试覆盖

参考 review 报告 `doing_plan.tmp/code-review-perl.md` 
相关章节： `## 四、测试覆盖缺口`。

用例优先按功能类别加在已有的 `*.t` 文件中，不好合并的才新建文件。

### DONE: 20260519-150223

## TODO:2026-05-19/3 封装 vim 插件应用 ai-chat.pl 于当前编辑的聊天文件

新建 vim/ 子目录，作为一个 git 子模块。
按标准 vim 插件组织其目录结构，允许用户单独 git clone 该子模块仓库至
~/.vim/pack/start (或 opt) 成为 vim 插件。

vim 插件单独仓库名打算在 github 上命名为 `chatedit-vim`，但嵌在这个主仓库时，
位于 `vim/` 子目录，也相当语言名称。未预建 `chatedit-vim` 仓库，能直接从 `vim/`
子目录新建仓库吗？

### vim 插件功能

自定义命令：
- `:AI` ，将当前编辑文件(buffer) ，用 `:!ai-chat.pl --reformat` ，捕获 stdout
  ，添加到 buffer 末尾。由于在 vim 中编辑，不要加 `--append` 参数，由用户在
  vim 中再决定保存修改的文件。但调用 `ai-chat.pl` 前先保存文件，除非 buffer
  还没关联文件名，那就先将 buffer 写入临时文件。即使能将 buffer 通过 stdin 传
  给 `ai-chat.pl` ，后者的实现也需要保存临时文件，不如统一先存盘。
- `:'<,>'AI` ，将当前选区保存临时文件，调用 `ai-chat.pl --reformat` ，捕获输出
  插到选区下面。`:AI` 的效果相当于 `:%AI` ，但在有文件名时不必另存临时文件。
- `:AR` 与 `:'<,>'AR`，调用 `ai-chat.pl --simple` 模式，并将输出替换当前文件或
  选区内容。

先为简单实现起见，用同步方式调用 `ai-chat.pl` 。这样在 vim7 以下老版本也能使用，
只是在 AI 返回之前可能 vim 无法使用，要卡一会。后面再优化为异常方式。

文件类型插件 ftplugin/markdown.vim 增加几个插入模式下的快捷缩写：
- `#s` 能展开为 `## system >>`
- `#u` 能展开为 `## user >>`
- `#a` 能展开为 `## assistant >>`

这用于快捷输出特殊的对话标题。

### 安装 ai-chat.pl

为了能在 vim 中方便调用 `ai-chat.pl` ，最好安装到 `$PATH` 中。

项目根目录写个简单 makefile ，支持一些伪目标：

- `make test`: 执行 prove 做单元测试
- `make install`: 将 `ai-chat.pl` 与 `ai-curl.sh` 拷到 `$HOME/bin/` 目录
- `make help`: 打印可选目标及功能用法

### DONE: 20260519-202210

## TODO:2026-05-20/1 vim 插件也捕获标准错误

让`:AI` 与 `:AR` 同时捕获标准输出与标准错误，在 ai-chat.pl 调用出错时，有输出。

出错时，状态栏在显示 `ErrorMsg` 之外，也将详细信息显示到 buffer ，展示给用户。
用户看过错误后，可自行删除错误信息，或用 `u` 撤销命令对 buffer 的修改。

检查一下 `ai-chat.pl` 在没有 `--debug` 选项时，正常路径不会有错误信息或调试信
息混入。

函数 `append_to_file` 还有小问题应修复一下，扫描文件仅为判断最后一行非空，性价
比低。直接加一个回车，保证二级标题顶格写即可。用户在使用 vim 编辑时可自行增删
空行。

### DONE: 20260520-091327

## TODO:2026-05-20/2 vim 插件异步调用 ai-chat.pl

本任务原则上只操作 vim/ 子仓库。

先提交当前 vim 的修改，新建个 `for-vim7` 分支保存当前状态。
再切回主分支 `main` 开发新功能。

当前 plugin/chatedit.vim 的主要内容可保留，但仅为了兼容老版本（低于 vim8，或没
有 +job 特性）。

在 autoload/chatedit.vim 中重写当前 `s:RunChat` 的实现，但用异步的方式调用
`ai-chat.pl` ，且加上 `--steam` 参数。使之在调用过程中 vim 不会卡死，且在流式
调用中能实时添加内容到当前 buffer 。

自定义命令 `:AI` 与 `:AR` 也改为调用 autload 函数。

当异步调用的 `ai-chat.pl` 结束返回时，优先保证用户仍在当前编辑 buffer 窗口的行
为正确性。再考虑其他异常情况，包括但不限于：
- 在当前 buffer 但不是普通模式
- 在其他窗口
- 在其他 tabpage
- 原 buffer 被隐藏
- 原 buffer 被删除

请设计符合 vim 用户交互直觉的方式来处理这些异常情况。

ftplugin/markdown.vim 增加两个普通模式下的快捷键，用 `>>` 与 `<<` 分别对标题行
增加或减少缩进，仅处理标题行，非标题行仍按默认行为。复杂逻辑可封装在 autoload
函数中。

vim/ 子目录补充独立的 readme 文档。

在 vim/ 子仓库提交代码。但 `task_todo.md` 与 `task_log.md` 保留在主仓库管理，
可以暂时不为这俩文档单独提交。

### DONE: 20260520-144608

## TODO:2026-05-21/1 添加版本标志及完善文档

ai-curl.sh 与 ai-chat.pl 添加 `--version|-v` 选项，打印版本号。
当前版本号定为 `1.0` 。
打算就用一个浮点数表示版本号，多位小数间不加额外点。
以后若要升版本，接近 e 或 pi 方向。

vim/autoload/chatedit.vim 也加个变量标记当前版本号 `1.0`

vim 插件还要补充一个文档，标准 vim 插件的帮助文档格式。

vim 插件子仓库有独立 readme 的话，主仓库的 readme 可精简些，再加链接。
主库说明自定义 `:AI/AR` 调用 `ai-chat` 工具即可，
编辑 markdown 的快捷键完全是 vim 插件的功能，与主库工具无关，不需要在主库体现。

### DONE: 20260521-095009

## TODO:2026-05-21/2 【bug】流式回复内容的标题没有纠正

在 vim 使用 `:AI` 或命令行 `ai-chat.pl --stream --reformat 1` 时，
有时发现输出内容仍有二级标题，以 `##` 开头。
这违反了多轮对话的格式约定。
请可能的原因，修复之。

我有两个方案：
1. 一是可以不管命令行工具打印到 stdout 的格式，只在 vim 插件中做后处理，全部输
出完时再扫描一遍修正标题等级。
2. 只缓存上一个 delta 末尾是否是有换行符，下一个 delta 以 `#` 开头时修正标题等
级。在一个 delta 内，也有可能出现 "\n#" 。不过这有个问题，只有行记忆，代码块的
标题也会被增加标题等级。

我还是倾向于第 2 方案。

事实上，当前的 `fix_heading_level` 函数也没有处理代码块保持功能，这种情况不如
代码块外频繁，先不改，但要注释或文档说明这种情况。

### DONE: 20260521-105750

## TODO:2026-05-21/3 【bug】流式响应处理加了很多额外的 0

上个任务对 `call_api_stream` 的修改，似乎引用了新 bug ，几乎每行有效内容的响应
都加了 `0` 字符。

请分析原因，修复。
同时补充单元测试用例，模拟流式响应，验证能正常处理。

### DONE: 20260521-122705

## TODO:2026-05-21/4 【重构】优化流式响应处理函数

前面连续对流式响应解决了两个 bug ，这也反映了这个过程的实现方式不尽合理，单元
测试覆盖不足。

所以建议重构`call_api_stream` 函数，把 `<$resp_fh>` 循环部分抽取为独立函数，以
便单元测试。

在 `local-chat/stream.json` 中保存了一份带 `--json` 选项的实际的 API 请求结果。
但文件有点大，没必要全部放入 `testdata/` 目录提交版本库。
可以做适当精简，构造流式响应的原始文件，覆盖各种边界情况。

在测试用例中也可以 mock `_extract_stream_delta` ，使之在循环读取中返回预设的纯
文本流。

### DONE: 20260521-153800

## TODO:2026-05-21/5 【增强】回复内容修正标题等级时处理代码块

当前 `fix_heading_level` 在代码块内也会增加标题等级。
修正标题等级的目的是为了多轮聊天重新解析，
而解析聊天文件时会忽略代码内的 `#` 标题，保持原样。

故为了行为对称性，`fix_heading_level`也应该保持代码内的标题等级。
难点在于流式处理时如何实时识别代码块的开启关闭状态。

可以考虑额外传入一个引入参数，表示当前是否在代码块内，
在该函数处理过程中可能切换该状态（行首三反引号）。

补充单元测试覆盖这个新功能。
`10-reformat.t` 的直接测试与 `13-stream-process.t` 的间接测试可能都要补充用例。

我已能考虑的特殊例外：
AI 流式响应不会将二级标题前缀 `##` 拆成两个 `#`，
也不会将三反引号拆成两个以上的 token 。
在这两种极端情况下可能处理失败，但正常的实际 AI 响应只能假设它会当成一个
token 输出。

### DONE: 20260521-162311

## TODO:2026-05-22/1 【设计】ai-chat.pl 迁移 python node 计划

请重新梳理当前 ai-chat.pl 的核心逻辑，准备迁移 python 与 node 的实现版本。
在 doing_plan.tmp/ 目录写两份详细设计说明。

- 复刻核心思路与行为逻辑
- 保持命令行参数的意义与用法
- 可以用各自流行稳定的包替换 curl 请求

假设实现完后，将脚本安装到 bin/ 后，用如下三者之一的软链接：

```
ln -s ai-chat.pl ai-chat
ln -s ai-chat.py ai-chat
ln -s ai-chat.js ai-chat
```

那么 `ai-chat` 应该表现出相同的功能。

ps: 我没用过 python 或 node 写过功能较复杂的程序，对其包管理功能不熟，请问安装
时能只安装一个脚本吗？它们的依赖包是否也要一起安装才能使用。

然后可以修改这个 `task_todo.md` 文档，拆分迁移任务，追加到末尾。
拆分粒度适中，最好能在 claude 等 agent 的一个会话上下文完成任务。

自动拆分的任务先只用无 ID 的 `TODO` ，决定正式实施时再手动赋 ID 。

### DONE: 20260522-122015

## TODO:2026-05-22/2 【迁移】Python 版 ai-chat.py 实现

参考设计文档 `doing_plan.tmp/ai-chat-python-design.md`，实现 `python/ai-chat.py`。
依赖：`pip install openai`（唯一第三方包），其余全部使用标准库。

**阶段一：核心骨架**
- 建立 `python/` 子目录，新建 `ai-chat.py`，添加 shebang `#!/usr/bin/env python3`
- 实现 `parseArgs`（argparse）、`loadEnv`、`findConfigFile` 三个函数
- 实现 `readFileContent`、`loadTemplate`（JSON 模板加载）
- 实现 `parseChat` 状态机（含 @file、!cmd 扩展）与 `normalizeRole`
- 实现 `injectSystem`、`decodeToMd`（--decode 模式）
- 验证：`python3 python/ai-chat.py --encode testdata/chat-hello.md | jq .`

**阶段二：API 调用与响应处理**
- 实现 `makeClient`（构造 openai.OpenAI，传入 base_url 与 api_key）
- 实现 `callApi`（`client.chat.completions.create` 非流式）
- 实现 `fixHeadingLevel`（含 in_code_state 参数）、`printResponse`、`appendToFile`
- 实现 `runNonStream`（两阶段输出逻辑）
- 验证：`python3 python/ai-chat.py -a testdata/chat-hello.md`（需有效 env）

**阶段三：流式响应**
- 实现 `callApiStream`（`client.chat.completions.stream` SDK 流式迭代器）
- 实现 `callApiRaw` / `callApiStreamRaw`（`with_raw_response` 支持 --json 选项）
- 实现 `runStream`
- 验证：`python3 python/ai-chat.py --stream -a testdata/chat-hello.md`

**阶段四：完善与测试**
- 实现 `openStdin`（含 --append 复制 stdin 到 stdout）
- 完成 `--version`、`--debug`、`--postdir`、`--simple` 等选项
- 编写 `python/tests/test_*.py` 单元测试（用内置 `unittest`）
- 更新 CLAUDE.md 与 Makefile（增加 python 相关 test/install 目标）

本地开发环境 .chatedit/ 子目录已配置有效的 kimi key，可供验证。
原来的 testdata/ 测试数据中立，可考虑复用。

### DONE: 20260522-173148

## TODO:2026-05-22/3 【迁移】Node.js 版 ai-chat.js 实现

参考设计文档 `doing_plan.tmp/ai-chat-node-design.md`，实现 `node/ai-chat.js`。
依赖：`npm install openai`（唯一第三方包），需 npm 包结构，通过 `npm install -g` 分发。

**阶段一：项目结构与核心骨架**
- 建立 `node/` 子目录，初始化 `package.json`（含 bin 入口、openai 依赖）
- 新建 `ai-chat.js`，添加 shebang，整体采用 async/await 架构
- 实现 `parseArgs`（手动解析 process.argv）、`loadEnv`、`findConfigFile`
- 实现 `readFileContent`、`loadTemplate`、`parseChat`、`normalizeRole`
- 实现 `injectSystem`、`decodeToMd`
- 验证：`node node/ai-chat.js --encode testdata/chat-hello.md`

**阶段二：API 调用与响应处理**
- `npm install` 安装 openai 包
- 实现 `makeClient`（构造 `new OpenAI({ baseURL, apiKey })`）
- 实现 `callApi`（`client.chat.completions.create` async 非流式）
- 实现 `fixHeadingLevel`、`printResponse`、`appendToFile`、`runNonStream`

**阶段三：流式响应**
- 实现 `callApiStream`（`client.chat.completions.stream` async 迭代器）
- 实现 `callApiRaw` / `callApiStreamRaw`（`withResponse` 支持 --json 选项）
- 实现 `runStream`

**阶段四：完善与测试**
- 实现 `openStdin`（async 读取 stdin，--append 复制到 stdout）
- 完成所有辅助选项
- 编写 `node/test/test_*.js` 单元测试（用内置 `node:test`，Node 18+）
- 更新 Makefile（增加 node 相关 test/install 目标）

### DONE: 20260523-150240

## TODO:2026-06-13/1 --reformat 选项功能优化

当前，`--reformat` 的取值好像只有 0 与 1，开启时对 API 响应的 markdown 标题固
定增加一级。

但是，我在使用中发现也有很多时候 API 的输出本身就是从三级标题开始的，然后就变
成四级标题位于 `## assistant >>` 二级标题下面，也不太合适。所以需要一定的智能
兼容判断。

修改为当 `--reformat=1` 时，仅在遇到一级或二标题之后，才采用原来的修正，增加一
级标题。如果整个输出最大标题也只有三级，那就不用纠正。

注意要同时处理流式与非流式的行为。否则通过修改 `fix_heading_level` 满足两者。
已经实现的 perl/python/node 版本都要同步修改。

### DONE: 20260613-210359

## TODO: 长期计划

尝试用不同的语言实现基本的 AI 聊天功能。

- [Y] bash 基本 curl 请求封装
- [Z] perl 实现
- [Z] vim 插件集成
- [O] 其他脚本实现如 python node
- [O] 编译型实现，供预编译可执行程序，如 cpp rust go
- [O] web 浏览器独立前端页面实现

图例：
- O: 未实施
- X: 取消实现
- Y: 已实施
- Z: 实施中
