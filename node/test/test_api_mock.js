// test_api_mock.js - 用 mock client 测试完整流程
'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { runNonStream, setOpt } = require('../ai-chat.js');

// 创建临时文件
function makeTempFile(content) {
    const tmpFile = path.join(os.tmpdir(), `chatedit-test-${process.pid}-${Date.now()}.md`);
    fs.writeFileSync(tmpFile, content);
    return tmpFile;
}

// 构造 mock client
function makeMockClient(role, content) {
    return {
        chat: {
            completions: {
                create: async () => ({
                    choices: [{ message: { role, content } }]
                })
            }
        }
    };
}

test('runNonStream: 基本响应输出到 stdout', async () => {
    setOpt({ debug: false, reformat: null, append: false, json: false, postdir: '' });

    const mockClient = makeMockClient('assistant', 'Hello world');
    const messages = [{ role: 'user', content: 'hi' }];

    // 捕获 stdout 输出
    const origWrite = process.stdout.write.bind(process.stdout);
    let captured = '';
    process.stdout.write = (data) => { captured += data; return true; };
    try {
        await runNonStream(mockClient, 'gpt-4', {}, messages, 'test.md');
    } finally {
        process.stdout.write = origWrite;
    }

    assert.ok(captured.includes('Hello world'));
});

test('runNonStream: --append 追加到文件', async () => {
    const tmpFile = makeTempFile('## user >> hi\n');
    setOpt({ debug: false, reformat: null, append: true, json: false, postdir: '' });

    const mockClient = makeMockClient('assistant', 'Hello from mock');
    const messages = [{ role: 'user', content: 'hi' }];

    // 静默 stderr 和 stdout
    const origStdout = process.stdout.write.bind(process.stdout);
    const origStderr = process.stderr.write.bind(process.stderr);
    process.stdout.write = () => true;
    process.stderr.write = () => true;
    try {
        await runNonStream(mockClient, 'gpt-4', {}, messages, tmpFile);
    } finally {
        process.stdout.write = origStdout;
        process.stderr.write = origStderr;
    }

    const fileContent = fs.readFileSync(tmpFile, 'utf-8');
    assert.ok(fileContent.includes('## assistant >>'));
    assert.ok(fileContent.includes('Hello from mock'));

    fs.unlinkSync(tmpFile);
});

test('runNonStream: reformat=1 时输出带标题行', async () => {
    setOpt({ debug: false, reformat: 1, append: false, json: false, postdir: '' });

    const mockClient = makeMockClient('assistant', 'content here');
    const messages = [{ role: 'user', content: 'test' }];

    let captured = '';
    const origWrite = process.stdout.write.bind(process.stdout);
    process.stdout.write = (data) => { captured += data; return true; };
    try {
        await runNonStream(mockClient, 'gpt-4', {}, messages, 'test.md');
    } finally {
        process.stdout.write = origWrite;
    }

    assert.ok(captured.includes('## assistant >>'));
    assert.ok(captured.includes('content here'));
});

test('runNonStream: reformat=0 时输出不含标题行', async () => {
    setOpt({ debug: false, reformat: 0, append: false, json: false, postdir: '' });

    const mockClient = makeMockClient('assistant', 'content here');
    const messages = [{ role: 'user', content: 'test' }];

    let captured = '';
    const origWrite = process.stdout.write.bind(process.stdout);
    process.stdout.write = (data) => { captured += data; return true; };
    try {
        await runNonStream(mockClient, 'gpt-4', {}, messages, 'test.md');
    } finally {
        process.stdout.write = origWrite;
    }

    assert.ok(!captured.includes('## assistant >>'));
    assert.ok(captured.includes('content here'));
});
