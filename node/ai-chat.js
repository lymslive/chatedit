#!/usr/bin/env node
// ai-chat.js - 将 markdown 聊天文件转换为 AI API 的 JSON 请求体并可直接发送请求
//
// 依赖：npm install openai（唯一第三方包，其余全部使用 Node.js 内置模块）
'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync } = require('child_process');

const VERSION = '1.0';

const progName = path.basename(process.argv[1]).replace(/\.(js|pl|py)$/, '');

// 全局选项（由 parseArgs 填充）
let opt = null;

// ============================================================================
// 主入口
// ============================================================================

async function main() {
    try {
        await run();
    } catch (e) {
        process.stderr.write(`错误: ${e.message}\n`);
        process.exit(1);
    }
}

async function run() {
    opt = parseArgs(process.argv);

    if (opt.version) {
        process.stdout.write(`${progName} ${VERSION}\n`);
        process.exit(0);
    }

    if (opt.help) {
        usage();
        process.exit(0);
    }

    if (opt.decode) {
        decodeToMd();
        process.exit(0);
    }

    loadEnv();

    if (opt.encode) {
        opt.append = false; // --encode 时 --append 无效
    }

    const inputFile = opt.input;

    let text;
    if (inputFile) {
        try {
            text = fs.readFileSync(inputFile, 'utf-8');
        } catch (e) {
            process.stderr.write(`错误: 无法打开文件 '${inputFile}': ${e.message}\n`);
            process.exit(1);
        }
        if (opt.debug) {
            process.stderr.write(`[debug] 输入文件: ${inputFile}\n`);
        }
    } else {
        text = await openStdin();
    }

    const template = loadTemplate();

    let messages;
    if (opt.simple) {
        const content = text.trimEnd();
        messages = [{ role: 'user', content }];
    } else {
        messages = parseChat(text);
    }

    injectSystem(messages);

    const modelVal = template.model || '';
    if (/\$\{?API_MODEL\}?/.test(modelVal)) {
        template.model = process.env.API_MODEL || modelVal;
    }

    const isStream = opt.stream || template.stream === true;
    if (isStream) {
        template.stream = true;
    }

    if (opt.encode) {
        template.messages = messages;
        process.stdout.write(JSON.stringify(template, null, 2) + '\n');
        process.exit(0);
    }

    const apiUrl = process.env.API_URL || '';
    const apiKey = process.env.API_KEY || '';
    if (!apiUrl) {
        process.stderr.write('错误: 未设置 API URL，请通过 --url 参数或 env 文件中的 API_URL 配置\n');
        process.exit(1);
    }
    if (!apiKey) {
        process.stderr.write('错误: 未设置 API KEY，请通过 --key 参数或 env 文件中的 API_KEY 配置\n');
        process.exit(1);
    }

    const model = template.model || '';

    if (opt.debug) {
        const masked = apiKey.length >= 10
            ? apiKey.slice(0, 6) + '****' + apiKey.slice(-4) : '****';
        process.stderr.write(`[debug] POST ${apiUrl} (key: ${masked})\n`);
        process.stderr.write(`[debug] model: ${model}\n`);
    }

    if (opt.postdir) {
        saveToPostdir(opt.postdir, template, messages);
    }

    let OpenAI;
    try {
        OpenAI = require('openai');
    } catch (e) {
        process.stderr.write('错误: 请先安装 openai 包：npm install openai\n');
        process.exit(1);
    }

    const client = makeClient(OpenAI, apiUrl, apiKey);

    if (isStream) {
        await runStream(client, model, template, messages, inputFile);
    } else {
        await runNonStream(client, model, template, messages, inputFile);
    }
}

// ============================================================================
// 参数解析
// ============================================================================

function parseArgs(argv) {
    const args = argv.slice(2);
    const opts = {
        template: null, debug: false, help: false,
        encode: false, decode: false, append: false,
        reformat: null,       // null = auto
        env: null, url: '', key: '', model: '',
        system: undefined,    // undefined=自动查找，''=抑止，其他=使用该值
        simple: false, json: false, postdir: '',
        stream: false, version: false,
        input: null,
    };
    for (let i = 0; i < args.length; i++) {
        const a = args[i];
        const next = () => args[++i];
        switch (a) {
            case '--template': case '-t': opts.template = next(); break;
            case '--debug':    case '-d': opts.debug = true; break;
            case '--help':     case '-h': opts.help = true; break;
            case '--encode':              opts.encode = true; break;
            case '--decode':              opts.decode = true; break;
            case '--append':   case '-a': opts.append = true; break;
            case '--reformat':            opts.reformat = parseInt(next(), 10); break;
            case '--env':                 opts.env = next(); break;
            case '--url':                 opts.url = next(); break;
            case '--key':                 opts.key = next(); break;
            case '--model':               opts.model = next(); break;
            case '--system':
                if (i + 1 < args.length && !args[i + 1].startsWith('-'))
                    opts.system = next();
                else
                    opts.system = '';
                break;
            case '--simple':   case '-s': opts.simple = true; break;
            case '--json':     case '-j': opts.json = true; break;
            case '--postdir':             opts.postdir = next(); break;
            case '--stream':              opts.stream = true; break;
            case '--version':  case '-v': opts.version = true; break;
            default:
                if (!a.startsWith('-')) opts.input = a;
                else {
                    process.stderr.write(`未知选项: ${a}\n`);
                    usage();
                    process.exit(1);
                }
        }
    }
    return opts;
}

// ============================================================================
// 配置文件查找
// ============================================================================

function findConfigFile(suffix) {
    const dirs = ['.', './.chatedit'];
    const home = process.env.HOME;
    if (home) dirs.push(path.join(home, '.chatedit'));

    const names = [`${progName}.${suffix}`];
    if (progName !== 'ai-chat') names.push(`ai-chat.${suffix}`);

    for (const name of names) {
        for (const dir of dirs) {
            const f = path.join(dir, name);
            try {
                if (fs.statSync(f).isFile()) {
                    if (opt && opt.debug) {
                        process.stderr.write(`[debug] 找到配置文件: ${f}\n`);
                    }
                    return f;
                }
            } catch {}
        }
    }
    return null;
}

function findEnvFile() { return findConfigFile('env'); }
function findSystemFile() { return findConfigFile('sys'); }
function findTemplateFile() { return findConfigFile('json'); }

// ============================================================================
// 环境加载
// ============================================================================

function loadEnv() {
    let envFile = null;

    if (opt.env !== null) {
        if (!opt.env) {
            if (opt.debug) {
                process.stderr.write('[debug] --env 指定为空，抑止 env 文件查找\n');
            }
        } else if (!fs.existsSync(opt.env)) {
            process.stderr.write(`警告: --env 指定的文件不存在: ${opt.env}\n`);
        } else {
            envFile = opt.env;
        }
    } else {
        envFile = findEnvFile();
    }

    if (envFile) {
        if (opt.debug) {
            process.stderr.write(`[debug] 加载 env 文件: ${envFile}\n`);
        }
        const lines = fs.readFileSync(envFile, 'utf-8').split('\n');
        for (const rawLine of lines) {
            const line = rawLine.trim();
            if (!line || line.startsWith('#')) continue;
            const m = line.match(/^(\w+)\s*=\s*(.*?)\s*$/);
            if (m) {
                let [, k, v] = m;
                // 去除可能的引号
                v = v.replace(/^(['"])(.*)\1$/, '$2');
                if (!(k in process.env)) {
                    process.env[k] = v;
                }
            }
        }
    }

    if (opt.url)   process.env.API_URL   = opt.url;
    if (opt.key)   process.env.API_KEY   = opt.key;
    if (opt.model) process.env.API_MODEL = opt.model;
}

// ============================================================================
// 模板加载
// ============================================================================

function defaultTemplate() {
    return '{"model":"$API_MODEL","messages":[]}';
}

function loadTemplate() {
    let file = null;

    if (opt.template !== null) {
        if (!opt.template) {
            if (opt.debug) {
                process.stderr.write('[debug] --template 指定为空，抑止模板文件查找\n');
            }
        } else if (!fs.existsSync(opt.template)) {
            process.stderr.write(`警告: --template 指定的文件不存在: ${opt.template}\n`);
        } else {
            file = opt.template;
        }
    } else {
        file = findTemplateFile();
    }

    let text;
    if (file) {
        if (opt.debug) {
            process.stderr.write(`[debug] 模板文件: ${file}\n`);
        }
        text = readFileContent(file);
    } else {
        if (opt.debug) {
            process.stderr.write('[debug] 使用内联默认模板\n');
        }
        text = defaultTemplate();
    }

    let data;
    try {
        data = JSON.parse(text);
    } catch (e) {
        process.stderr.write(`错误: 模板 JSON 解析失败: ${e.message}\n`);
        process.exit(1);
    }

    // 删除 messages 字段（由 parseChat 填充）
    delete data.messages;
    return data;
}

// ============================================================================
// stdin 处理
// ============================================================================

async function openStdin() {
    if (opt.debug) {
        process.stderr.write('[debug] 从 STDIN 读取输入\n');
    }
    return new Promise((resolve, reject) => {
        const chunks = [];
        if (opt.append) {
            process.stdin.on('data', (chunk) => {
                chunks.push(chunk);
                process.stdout.write(chunk);
            });
            process.stdin.on('end', () => {
                const buf = Buffer.concat(chunks);
                // 补尾部换行
                if (buf.length > 0 && buf[buf.length - 1] !== 10) {
                    process.stdout.write('\n');
                }
                resolve(buf.toString('utf-8'));
            });
        } else {
            process.stdin.on('data', c => chunks.push(c));
            process.stdin.on('end', () => resolve(Buffer.concat(chunks).toString('utf-8')));
        }
        process.stdin.on('error', reject);
    });
}

// ============================================================================
// Markdown 聊天解析（同步）
// ============================================================================

const ROLE_ABBR = { P: 'system', Q: 'user', A: 'assistant' };

function normalizeRole(raw) {
    return ROLE_ABBR[raw.toUpperCase()] || raw.toLowerCase();
}

function includeFile(filePath) {
    if (!fs.existsSync(filePath)) {
        process.stderr.write(`警告: 引用文件不存在: ${filePath}\n`);
        return [false];
    }
    try {
        const content = fs.readFileSync(filePath, 'utf-8');
        const lines = content.split('\n').map(l => l.replace(/\n$/, ''));
        // 去掉末尾多余的空行（readFileSync 末尾通常有 \n）
        if (lines.length > 0 && lines[lines.length - 1] === '') lines.pop();
        return [true, ...lines];
    } catch (e) {
        process.stderr.write(`警告: 无法读取文件 '${filePath}': ${e.message}\n`);
        return [false];
    }
}

function runCommand(cmd) {
    if (opt && opt.debug) {
        process.stderr.write(`[debug] 执行命令: ${cmd}\n`);
    }
    try {
        const output = execSync(cmd, { encoding: 'utf-8', stdio: ['pipe', 'pipe', 'pipe'] });
        const trimmed = output.replace(/\n$/, '');
        return [true, ...trimmed.split('\n')];
    } catch (e) {
        process.stderr.write(`警告: 命令执行失败 (${cmd}): ${e.message}\n`);
        return [false];
    }
}

function parseChat(text) {
    const messages = [];
    let curRole = '', curLines = [], inCode = false;

    function flush() {
        if (curRole) {
            const content = curLines.join('\n').replace(/^\n+/, '').replace(/\n+$/, '');
            messages.push({ role: curRole, content });
            curRole = '';
            curLines = [];
        }
    }

    for (const line of text.split('\n')) {
        if (line.startsWith('```')) {
            inCode = !inCode;
            if (curRole) curLines.push(line);
            continue;
        }
        if (inCode) {
            if (curRole) curLines.push(line);
            continue;
        }

        const m = line.match(/^##\s+(system|user|assistant|[PQA])\s*>>(.*)/i);
        if (m) {
            flush();
            curRole = normalizeRole(m[1]);
            const rest = m[2].trimStart();
            curLines = rest ? [rest] : [];
            continue;
        }

        // ## 非角色标题或 # 注释行：结束当前段落
        if (/^##([^#]|$)/.test(line) || /^#([^#]|$)/.test(line)) {
            flush();
            continue;
        }

        if (curRole) {
            const atM = line.match(/^@\s*(\S.*)$/);
            if (atM) {
                const [ok, ...lines] = includeFile(atM[1].trimEnd());
                if (ok && lines.some(l => l.trim())) {
                    curLines.push(...lines);
                } else {
                    curLines.push(`${line} (${ok ? 'Read Empty' : 'Read Error'})`);
                }
                continue;
            }

            const bangM = line.match(/^!\s*(\S.*)$/);
            if (bangM) {
                const [ok, ...lines] = runCommand(bangM[1].trimEnd());
                if (ok && lines.some(l => l.trim())) {
                    curLines.push(...lines);
                } else {
                    curLines.push(`${line} (${ok ? 'Read Empty' : 'Read Error'})`);
                }
                continue;
            }

            curLines.push(line);
        }
    }
    flush();
    return messages;
}

// ============================================================================
// 系统消息注入
// ============================================================================

function injectSystem(messages) {
    let sysContent = null;

    if (opt.system !== undefined) {
        if (opt.system && opt.system !== '0') {
            sysContent = opt.system;
            const m = sysContent.match(/^@(.+)/);
            if (m) {
                sysContent = readFileContent(m[1].trim());
            }
        }
        // '' 或 '0' → 抑止，不插入
    } else {
        const sysFile = findSystemFile();
        if (sysFile) {
            if (opt.debug) {
                process.stderr.write(`[debug] 使用 system 文件: ${sysFile}\n`);
            }
            sysContent = readFileContent(sysFile);
        }
    }

    if (sysContent) {
        if (!messages.length || messages[0].role !== 'system') {
            messages.unshift({ role: 'system', content: sysContent });
        }
    }
}

// ============================================================================
// --decode 模式
// ============================================================================

function decodeToMd() {
    let jsonBytes;
    const inputFile = opt ? opt.input : null;

    if (inputFile) {
        try {
            jsonBytes = fs.readFileSync(inputFile, 'utf-8');
        } catch (e) {
            process.stderr.write(`错误: 无法打开文件 '${inputFile}': ${e.message}\n`);
            process.exit(1);
        }
    } else {
        jsonBytes = fs.readFileSync('/dev/stdin', 'utf-8');
    }

    let data;
    try {
        data = JSON.parse(jsonBytes);
    } catch (e) {
        process.stderr.write(`错误: 无法解析 JSON: ${e.message}\n`);
        process.exit(1);
    }

    for (const msg of data.messages || []) {
        const role = msg.role || 'unknown';
        const content = msg.content || '';
        process.stdout.write(`## ${role} >>\n\n${content}\n\n`);
    }
}

// ============================================================================
// 工具函数
// ============================================================================

function readFileContent(filePath) {
    try {
        return fs.readFileSync(filePath, 'utf-8').trim();
    } catch (e) {
        process.stderr.write(`错误: 无法读取文件 '${filePath}': ${e.message}\n`);
        process.exit(1);
    }
}

function saveToPostdir(directory, template, messages) {
    if (!fs.existsSync(directory) || !fs.statSync(directory).isDirectory()) {
        process.stderr.write(`警告: --postdir 目录不存在: ${directory}\n`);
        return;
    }
    const now = new Date();
    const ts = now.toISOString().replace(/[-:T]/g, '').slice(0, 15).replace(/(\d{8})(\d{6}).*/, '$1-$2');
    const req = Object.assign({}, template, { messages });
    const fname = path.join(directory, `${progName}-${ts}-${process.pid}.json`);
    try {
        fs.writeFileSync(fname, JSON.stringify(req, null, 2), 'utf-8');
        if (opt.debug) {
            process.stderr.write(`[debug] 已保存请求 JSON: ${fname}\n`);
        }
    } catch (e) {
        process.stderr.write(`警告: 无法写入 postdir 文件 '${fname}': ${e.message}\n`);
    }
}

// ============================================================================
// 响应格式化（同步）
// ============================================================================

function fixHeadingLevel(content, inCodeState) {
    const state = inCodeState || [false];
    const lines = content.split('\n');
    let count = 0;
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (line.startsWith('```')) { state[0] = !state[0]; continue; }
        if (state[0] || !line.startsWith('#')) continue;
        count++;
        const level = line.match(/^(#+)/)[1].length;
        if (level === 1)    lines[i] = '##' + line;   // # → ###
        else if (level < 6) lines[i] = '#' + line;    // h2→h3, ..., h5→h6
        // level >= 6: 已到最大标题级，保持不变
    }
    return [lines.join('\n'), count];
}

function printResponse(role, content, forFile) {
    const doFmt = opt.reformat !== null ? opt.reformat : (forFile ? 1 : 0);
    if (doFmt) {
        content = fixHeadingLevel(content)[0];
    }
    if (doFmt) {
        process.stdout.write(`## ${role} >>\n\n`);
    }
    process.stdout.write(content + '\n');
}

function appendToFile(filePath, role, content) {
    const doFmt = opt.reformat !== null ? opt.reformat : 1;

    let reformedCount = 0;
    if (doFmt) {
        [content, reformedCount] = fixHeadingLevel(content);
    }

    try {
        const fd = fs.openSync(filePath, 'a');
        fs.writeSync(fd, '\n');
        let linesAppended = 0;
        if (doFmt) {
            fs.writeSync(fd, `## ${role} >>\n\n`);
            linesAppended += 2;
        }
        const contentLines = content.split('\n');
        linesAppended += contentLines.length;
        fs.writeSync(fd, content + '\n');
        fs.closeSync(fd);
        return [linesAppended, reformedCount];
    } catch (e) {
        process.stderr.write(`错误: 无法写入文件 '${filePath}': ${e.message}\n`);
        process.exit(1);
    }
}

// ============================================================================
// API 客户端
// ============================================================================

function makeClient(OpenAI, apiUrl, apiKey) {
    // openai SDK 的 base_url 只需到 /v1，SDK 会自动追加具体端点
    const baseURL = apiUrl.replace(/\/chat\/completions$/, '');
    return new OpenAI({ baseURL, apiKey });
}

// ============================================================================
// API 调用：非流式
// ============================================================================

async function callApi(client, model, messages) {
    const resp = await client.chat.completions.create({ model, messages });
    const choice = resp.choices[0];
    return [choice.message.role || 'assistant', choice.message.content || ''];
}

async function callApiRaw(client, model, messages) {
    const { response } = await client.chat.completions.create({ model, messages }).withResponse();
    const text = await response.text();
    process.stdout.write(text);
}

// ============================================================================
// API 调用：流式
// ============================================================================

async function callApiStream(client, model, messages, reformat) {
    let role = 'assistant', content = '';
    let rolePrinted = false, prevEndsNl = true;
    const inCodeState = [false];

    const stream = await client.chat.completions.create({ model, messages, stream: true });
    for await (const chunk of stream) {
        const delta = chunk.choices[0] && chunk.choices[0].delta;
        if (!delta) continue;
        if (delta.role) role = delta.role;
        const deltaText = delta.content || '';
        if (!deltaText) continue;

        if (reformat && !rolePrinted) {
            process.stdout.write(`## ${role} >>\n\n`);
            rolePrinted = true;
            prevEndsNl = true;
        }

        if (reformat) {
            if (prevEndsNl) {
                process.stdout.write(fixHeadingLevel(deltaText, inCodeState)[0]);
            } else if (deltaText.includes('\n')) {
                const nlPos = deltaText.indexOf('\n');
                process.stdout.write(
                    deltaText.slice(0, nlPos + 1) +
                    fixHeadingLevel(deltaText.slice(nlPos + 1), inCodeState)[0]
                );
            } else {
                process.stdout.write(deltaText);
            }
        } else {
            process.stdout.write(deltaText);
        }

        content += deltaText;
        prevEndsNl = deltaText.endsWith('\n');
    }
    return [role, content];
}

async function callApiStreamRaw(client, model, messages) {
    const stream = await client.chat.completions.create({ model, messages, stream: true });
    for await (const chunk of stream) {
        // 输出原始 SSE 事件的 JSON 表示
        process.stdout.write('data: ' + JSON.stringify(chunk) + '\n');
    }
    process.stdout.write('data: [DONE]\n');
}

// ============================================================================
// 运行模式：非流式
// ============================================================================

async function runNonStream(client, model, template, messages, inputFile) {
    if (opt.json) {
        await callApiRaw(client, model, messages);
        return;
    }

    let role, content;
    try {
        [role, content] = await callApi(client, model, messages);
    } catch (e) {
        process.stderr.write(`错误: API 调用失败: ${e.message}\n`);
        process.exit(1);
    }

    if (opt.append && inputFile === null) {
        // stdin 模式：输出到 stdout（已在 openStdin 中复制原输入）
        printResponse(role, content, true);
    } else {
        printResponse(role, content, false);

        if (opt.append && inputFile !== null) {
            const [linesAppended, reformed] = appendToFile(inputFile, role, content);
            process.stderr.write(
                `# <!-- ${linesAppended} lines appended to file: ${inputFile}; ` +
                `reformated lines: ${reformed} -->\n`
            );
        }
    }
}

// ============================================================================
// 运行模式：流式
// ============================================================================

async function runStream(client, model, template, messages, inputFile) {
    if (opt.json) {
        await callApiStreamRaw(client, model, messages);
        return;
    }

    let stdoutReformat;
    if (opt.append && inputFile === null) {
        stdoutReformat = opt.reformat !== null ? opt.reformat : 1;
    } else {
        stdoutReformat = opt.reformat !== null ? opt.reformat : 0;
    }

    let role, content;
    try {
        [role, content] = await callApiStream(client, model, messages, stdoutReformat);
    } catch (e) {
        process.stderr.write(`错误: 流式 API 调用失败: ${e.message}\n`);
        process.exit(1);
    }

    if (content && !content.endsWith('\n')) {
        process.stdout.write('\n');
    }

    if (opt.append && inputFile !== null) {
        const [linesAppended, reformed] = appendToFile(inputFile, role, content);
        process.stderr.write(
            `# <!-- ${linesAppended} lines appended to file: ${inputFile}; ` +
            `reformated lines: ${reformed} -->\n`
        );
    }
}

// ============================================================================
// 帮助信息
// ============================================================================

function usage() {
    process.stderr.write(`\
用法: ${progName} [选项] [input.md]
      ${progName} [选项] < input.md

将 Markdown 聊天文件解析为 AI API JSON 并直接发送请求，回复打印至 stdout；
可同时通过 --append/-a 将回复追加到输入文件。

选项（API 连接）:
  --env <file>       指定 env 文件（默认按优先级搜索 ai-chat.env）
  --url <url>        API URL（覆盖 env 文件 API_URL）
  --key <key>        API Key（覆盖 env 文件 API_KEY）
  --model <model>    模型名（覆盖 env 文件 API_MODEL）
  --system [msg]     system 消息；以 @ 开头时读取文件；不带参数时抑止自动查找
  -t, --template <file>  指定 JSON 模板文件

选项（行为）:
  -a, --append       将 AI 回复追加到输入 .md 文件；STDIN 模式则先将原输入复制到 stdout
  --reformat 0|1     控制格式化输出（0=关，1=开）；追加文件时默认 1，stdout 时默认 0
  -s, --simple       将整个输入当成简单 user 消息，跳过 Markdown 解析
  --stream           启用流式响应（SSE）

选项（调试）:
  --encode           只输出组装的 JSON（pretty），不发送请求
  --decode           逆向：输入 API JSON，输出 Markdown 对话段
  -j, --json         直接输出原始 API 响应 JSON，忽略 -a
  --postdir <dir>    将请求 JSON 保存到指定目录
  -d, --debug        打印调试信息到 stderr
  -v, --version      显示版本号
  -h, --help         显示此帮助

env 文件搜索顺序（PROG 为脚本名去掉 .js 后缀，如软链接 kimi-chat 则为 kimi-chat）:
  1. --env 指定的文件
  2. ./$PROG.env  （再回退 ./ai-chat.env）
  3. ./.chatedit/$PROG.env  （再回退 ./.chatedit/ai-chat.env）
  4. ~/.chatedit/$PROG.env  （再回退 ~/.chatedit/ai-chat.env）
`);
}

// ============================================================================
// 模块导出（供测试使用）
// ============================================================================

module.exports = {
    parseArgs,
    findConfigFile,
    loadEnv,
    loadTemplate,
    parseChat,
    normalizeRole,
    includeFile,
    runCommand,
    injectSystem,
    decodeToMd,
    readFileContent,
    fixHeadingLevel,
    printResponse,
    appendToFile,
    makeClient,
    callApi,
    callApiStream,
    runNonStream,
    runStream,
    getOpt: () => opt,
    setOpt: (o) => { opt = o; },
};

// ============================================================================
// 入口
// ============================================================================

if (require.main === module) {
    main();
}
