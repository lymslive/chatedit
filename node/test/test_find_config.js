// test_find_config.js - 测试 findConfigFile / loadEnv 函数
'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { findConfigFile, loadEnv, setOpt } = require('../ai-chat.js');

// 辅助：创建临时目录结构
function makeTempDir() {
    return fs.mkdtempSync(path.join(os.tmpdir(), 'chatedit-test-'));
}

test('当前目录优先找到 ai-chat.env', () => {
    const tmpDir = makeTempDir();
    const origCwd = process.cwd();
    try {
        process.chdir(tmpDir);
        setOpt({ debug: false });
        // 写入 ai-chat.env
        fs.writeFileSync(path.join(tmpDir, 'ai-chat.env'), 'API_URL=http://test\n');
        const found = findConfigFile('env');
        assert.equal(found, path.join('.', 'ai-chat.env'));
    } finally {
        process.chdir(origCwd);
        fs.rmSync(tmpDir, { recursive: true });
    }
});

test('未找到时返回 null', () => {
    const tmpDir = makeTempDir();
    const origCwd = process.cwd();
    const savedHome = process.env.HOME;
    // 使用一个空的临时 HOME 目录，确保 ~/.chatedit/ 中也不存在该文件
    const tmpHome = makeTempDir();
    try {
        process.chdir(tmpDir);
        process.env.HOME = tmpHome;
        setOpt({ debug: false });
        const found = findConfigFile('env');
        assert.equal(found, null);
    } finally {
        process.env.HOME = savedHome;
        process.chdir(origCwd);
        fs.rmSync(tmpDir, { recursive: true });
        fs.rmSync(tmpHome, { recursive: true });
    }
});

test('loadEnv 将 env 文件变量加载到 process.env', () => {
    const tmpDir = makeTempDir();
    const origCwd = process.cwd();
    // 保存/恢复环境变量
    const savedUrl = process.env.API_URL;
    delete process.env.API_URL;
    try {
        process.chdir(tmpDir);
        setOpt({ debug: false, env: null, url: '', key: '', model: '' });
        fs.writeFileSync(path.join(tmpDir, 'ai-chat.env'), 'API_URL=http://from-env\n');
        loadEnv();
        assert.equal(process.env.API_URL, 'http://from-env');
    } finally {
        if (savedUrl === undefined) delete process.env.API_URL;
        else process.env.API_URL = savedUrl;
        process.chdir(origCwd);
        fs.rmSync(tmpDir, { recursive: true });
    }
});

test('loadEnv 不覆盖已存在的环境变量', () => {
    const tmpDir = makeTempDir();
    const origCwd = process.cwd();
    const savedUrl = process.env.API_URL;
    process.env.API_URL = 'http://already-set';
    try {
        process.chdir(tmpDir);
        setOpt({ debug: false, env: null, url: '', key: '', model: '' });
        fs.writeFileSync(path.join(tmpDir, 'ai-chat.env'), 'API_URL=http://from-env\n');
        loadEnv();
        assert.equal(process.env.API_URL, 'http://already-set');
    } finally {
        if (savedUrl === undefined) delete process.env.API_URL;
        else process.env.API_URL = savedUrl;
        process.chdir(origCwd);
        fs.rmSync(tmpDir, { recursive: true });
    }
});

test('loadEnv: --url 覆盖 env 文件', () => {
    const tmpDir = makeTempDir();
    const origCwd = process.cwd();
    const savedUrl = process.env.API_URL;
    delete process.env.API_URL;
    try {
        process.chdir(tmpDir);
        setOpt({ debug: false, env: null, url: 'http://override', key: '', model: '' });
        loadEnv();
        assert.equal(process.env.API_URL, 'http://override');
    } finally {
        if (savedUrl === undefined) delete process.env.API_URL;
        else process.env.API_URL = savedUrl;
        process.chdir(origCwd);
        fs.rmSync(tmpDir, { recursive: true });
    }
});
