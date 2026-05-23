// test_fix_heading.js - 测试 fixHeadingLevel 函数
'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { fixHeadingLevel } = require('../ai-chat.js');

test('h1 → h3（在原来 # 前加 ##）', () => {
    const [result, count] = fixHeadingLevel('# Hello');
    assert.equal(result, '### Hello');
    assert.equal(count, 1);
});

test('h2 → h3', () => {
    const [result, count] = fixHeadingLevel('## Hello');
    assert.equal(result, '### Hello');
    assert.equal(count, 1);
});

test('h3 → h4', () => {
    const [result] = fixHeadingLevel('### Hello');
    assert.equal(result, '#### Hello');
});

test('h5 → h6', () => {
    const [result] = fixHeadingLevel('##### Hello');
    assert.equal(result, '###### Hello');
});

test('h6 保持不变', () => {
    const [result] = fixHeadingLevel('###### Hello');
    assert.equal(result, '###### Hello');
});

test('非标题行不变', () => {
    const [result, count] = fixHeadingLevel('normal text');
    assert.equal(result, 'normal text');
    assert.equal(count, 0);
});

test('多行混合', () => {
    const input = '# Title\nsome text\n## Section\nmore text';
    const [result] = fixHeadingLevel(input);
    assert.equal(result, '### Title\nsome text\n### Section\nmore text');
});

test('代码块内的标题不修改', () => {
    const input = '```\n# code comment\n```\n# real heading';
    const [result] = fixHeadingLevel(input);
    assert.equal(result, '```\n# code comment\n```\n### real heading');
});

test('跨调用保持代码块状态', () => {
    const state = [false];
    // 第一次调用：进入代码块但未关闭
    const [r1] = fixHeadingLevel('```\n# in code', state);
    assert.equal(r1, '```\n# in code');
    assert.equal(state[0], true);
    // 第二次调用：仍在代码块内，关闭后正常标题
    const [r2] = fixHeadingLevel('# still in code\n```\n# after code', state);
    assert.equal(r2, '# still in code\n```\n### after code');
    assert.equal(state[0], false);
});
