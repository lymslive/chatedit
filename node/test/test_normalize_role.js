// test_normalize_role.js - 测试 normalizeRole 函数
'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { normalizeRole } = require('../ai-chat.js');

test('小写完整角色名保持不变', () => {
    assert.equal(normalizeRole('system'), 'system');
    assert.equal(normalizeRole('user'), 'user');
    assert.equal(normalizeRole('assistant'), 'assistant');
});

test('大写转小写', () => {
    assert.equal(normalizeRole('System'), 'system');
    assert.equal(normalizeRole('USER'), 'user');
    assert.equal(normalizeRole('ASSISTANT'), 'assistant');
});

test('缩写 P → system', () => {
    assert.equal(normalizeRole('P'), 'system');
    assert.equal(normalizeRole('p'), 'system');
});

test('缩写 Q → user', () => {
    assert.equal(normalizeRole('Q'), 'user');
    assert.equal(normalizeRole('q'), 'user');
});

test('缩写 A → assistant', () => {
    assert.equal(normalizeRole('A'), 'assistant');
    assert.equal(normalizeRole('a'), 'assistant');
});
