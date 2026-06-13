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

test('h3 无触发时不变', () => {
    const [result, count] = fixHeadingLevel('### Hello');
    assert.equal(result, '### Hello');
    assert.equal(count, 0);
});

test('h5 无触发时不变', () => {
    const [result, count] = fixHeadingLevel('##### Hello');
    assert.equal(result, '##### Hello');
    assert.equal(count, 0);
});

test('h6 无触发时 count=0', () => {
    const [result, count] = fixHeadingLevel('###### Hello');
    assert.equal(result, '###### Hello');
    assert.equal(count, 0);
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

test('跨调用保持 hasTopHeading 智能触发状态', () => {
    const hasTop = [false];
    // 第一次调用：只有 h3，无触发
    const [r1, c1] = fixHeadingLevel('### Section\ncontent\n', null, hasTop);
    assert.equal(c1, 0);
    assert.equal(hasTop[0], false);
    assert.ok(r1.includes('### Section'));

    // 第二次调用：h2 触发，后续 h3 修正
    const [r2, c2] = fixHeadingLevel('## Title\n### Detail\n', null, hasTop);
    assert.equal(hasTop[0], true);
    assert.equal(c2, 2);
    assert.ok(r2.includes('### Title'));
    assert.ok(r2.includes('#### Detail'));

    // 第三次调用：状态保持，继续修正
    const [r3, c3] = fixHeadingLevel('### More\n', null, hasTop);
    assert.equal(hasTop[0], true);
    assert.equal(c3, 1);
    assert.ok(r3.includes('#### More'));
});

test('inCodeState 与 hasTopHeading 可同时使用', () => {
    const inCode = [false];
    const hasTop = [false];
    const [r] = fixHeadingLevel(
        '### Before\n```\n## inside\n```\n## Trigger\n### After\n',
        inCode, hasTop
    );
    assert.equal(inCode[0], false);
    assert.equal(hasTop[0], true);
    assert.ok(r.includes('### Before'));   // 触发前不变
    assert.ok(r.includes('## inside'));    // 代码块内不变
    assert.ok(r.includes('### Trigger'));  // h2 自身修正
    assert.ok(r.includes('#### After'));   // 触发后 h3 修正
});
