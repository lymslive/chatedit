// test_parse_chat.js - 测试 parseChat 函数
'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { parseChat, setOpt } = require('../ai-chat.js');

// 初始化 opt，避免 null 引用
setOpt({ debug: false, reformat: null, append: false });

test('基本 user+assistant 对话', () => {
    const text = '## user >> hello\n\nworld\n\n## assistant >>\n\nhi there';
    const msgs = parseChat(text);
    assert.equal(msgs.length, 2);
    assert.equal(msgs[0].role, 'user');
    assert.equal(msgs[0].content, 'hello\n\nworld');
    assert.equal(msgs[1].role, 'assistant');
    assert.equal(msgs[1].content, 'hi there');
});

test('行内内容（>> 后接文本）', () => {
    const text = '## user >> ask something\n## assistant >> answer';
    const msgs = parseChat(text);
    assert.equal(msgs[0].content, 'ask something');
    assert.equal(msgs[1].content, 'answer');
});

test('缩写角色 P/Q/A', () => {
    const text = '## P >> sys\n## Q >> usr\n## A >> ans';
    const msgs = parseChat(text);
    assert.equal(msgs[0].role, 'system');
    assert.equal(msgs[1].role, 'user');
    assert.equal(msgs[2].role, 'assistant');
});

test('# 开头的注释行会分割段落', () => {
    const text = '## user >> hello\n# this is a comment\n## assistant >> world';
    const msgs = parseChat(text);
    assert.equal(msgs.length, 2);
    assert.equal(msgs[0].content, 'hello');
});

test('## 非角色标题结束段落', () => {
    const text = '## user >> hello\n## not a role\n## assistant >> world';
    const msgs = parseChat(text);
    assert.equal(msgs.length, 2);
    assert.equal(msgs[0].content, 'hello');
});

test('代码块内的 ## 不触发分割', () => {
    const text = '## user >>\n\n```\n## fake heading\n```\n\nmore text';
    const msgs = parseChat(text);
    assert.equal(msgs.length, 1);
    assert.ok(msgs[0].content.includes('## fake heading'));
    assert.ok(msgs[0].content.includes('more text'));
});

test('代码块内的 # 不作为注释', () => {
    const text = '## user >>\n```\n# comment in code\n```';
    const msgs = parseChat(text);
    assert.equal(msgs.length, 1);
    assert.ok(msgs[0].content.includes('# comment in code'));
});

test('空文本返回空数组', () => {
    assert.deepEqual(parseChat(''), []);
});

test('只有注释行返回空数组', () => {
    assert.deepEqual(parseChat('# title\n# another comment'), []);
});

test('内容首尾多余空行被 strip', () => {
    const text = '## user >>\n\n\nsome content\n\n\n## assistant >> reply';
    const msgs = parseChat(text);
    assert.equal(msgs[0].content, 'some content');
});
