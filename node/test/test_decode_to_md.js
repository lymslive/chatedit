// test_decode_to_md.js - 测试 decodeToMd 功能（通过子进程调用）
'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');

const AI_CHAT = path.join(__dirname, '..', 'ai-chat.js');
const TESTDATA = path.join(__dirname, '..', '..', 'testdata');

test('--decode 将 JSON 转换为 Markdown', () => {
    const jsonInput = JSON.stringify({
        messages: [
            { role: 'user', content: 'hello' },
            { role: 'assistant', content: 'world' }
        ]
    });

    const output = execSync(`echo '${jsonInput}' | node ${AI_CHAT} --decode`, {
        encoding: 'utf-8'
    });

    assert.ok(output.includes('## user >>'));
    assert.ok(output.includes('hello'));
    assert.ok(output.includes('## assistant >>'));
    assert.ok(output.includes('world'));
});

test('--encode 将 Markdown 转换为 JSON', () => {
    // 创建临时输入文件
    const tmpFile = path.join(os.tmpdir(), `decode-test-${process.pid}.md`);
    fs.writeFileSync(tmpFile, '## user >> test message\n\nbody text\n');
    try {
        const output = execSync(
            `node ${AI_CHAT} --encode --env "" ${tmpFile}`,
            { encoding: 'utf-8', env: Object.assign({}, process.env, { API_MODEL: 'test-model' }) }
        );
        const data = JSON.parse(output);
        assert.ok(Array.isArray(data.messages));
        assert.equal(data.messages.length, 1);
        assert.equal(data.messages[0].role, 'user');
        assert.ok(data.messages[0].content.includes('test message'));
    } finally {
        fs.unlinkSync(tmpFile);
    }
});
