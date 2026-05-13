#!/usr/bin/env perl
# 测试 parse_response 函数：解析 API 响应 JSON
use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use JSON::PP;

require "$Bin/../ai-chat.pl";

# ---- OpenAI 兼容格式 ---------------------------------------------------------
{
    my $json = JSON::PP->new->utf8->encode({
        choices => [{ message => { role => 'assistant', content => 'Hello!' } }]
    });
    my ($role, $content) = parse_response($json);
    is( $role,    'assistant', 'OpenAI: role' );
    is( $content, 'Hello!',    'OpenAI: content' );
}

# ---- OpenAI 格式：缺少 role 字段默认 assistant -------------------------------
{
    my $json = JSON::PP->new->utf8->encode({
        choices => [{ message => { content => 'No role key' } }]
    });
    my ($role, $content) = parse_response($json);
    is( $role,    'assistant',   'OpenAI missing role defaults to assistant' );
    is( $content, 'No role key', 'OpenAI missing role: content still extracted' );
}

# ---- Anthropic 原生格式 ------------------------------------------------------
{
    my $json = JSON::PP->new->utf8->encode({
        role    => 'assistant',
        content => [{ type => 'text', text => 'Hi from Claude' }]
    });
    my ($role, $content) = parse_response($json);
    is( $role,    'assistant',      'Anthropic: role' );
    is( $content, 'Hi from Claude', 'Anthropic: content' );
}

# ---- Anthropic 多 content 块拼接 ---------------------------------------------
{
    my $json = JSON::PP->new->utf8->encode({
        role    => 'assistant',
        content => [
            { type => 'text', text => 'Part one. ' },
            { type => 'text', text => 'Part two.' },
        ]
    });
    my ($role, $content) = parse_response($json);
    is( $content, 'Part one. Part two.', 'Anthropic: multiple content blocks joined' );
}

# ---- Anthropic 缺少 role 字段默认 assistant ----------------------------------
{
    my $json = JSON::PP->new->utf8->encode({
        content => [{ type => 'text', text => 'text' }]
    });
    my ($role, $content) = parse_response($json);
    is( $role, 'assistant', 'Anthropic missing role defaults to assistant' );
}

# ---- 无效 JSON ---------------------------------------------------------------
{
    open my $old_err, '>&', \*STDERR or die $!;
    open STDERR, '>', '/dev/null' or die $!;
    my ($role, $content) = parse_response('not valid json {{{');
    open STDERR, '>&', $old_err or die $!;

    is( $role,    undef, 'invalid JSON: role is undef' );
    is( $content, undef, 'invalid JSON: content is undef' );
}

# ---- 错误响应（含 error 字段，无 choices/content）---------------------------
{
    my $json = JSON::PP->new->utf8->encode({ error => { message => 'quota exceeded' } });
    my ($role, $content) = parse_response($json);
    is( $role,    undef, 'error response: role is undef' );
    is( $content, undef, 'error response: content is undef' );
}

# ---- 空 choices 数组 ---------------------------------------------------------
{
    my $json = JSON::PP->new->utf8->encode({ choices => [] });
    my ($role, $content) = parse_response($json);
    is( $role,    undef, 'empty choices: role is undef' );
    is( $content, undef, 'empty choices: content is undef' );
}

# ---- 空 content 数组 (Anthropic) ---------------------------------------------
{
    my $json = JSON::PP->new->utf8->encode({ role => 'assistant', content => [] });
    my ($role, $content) = parse_response($json);
    is( $role,    undef, 'empty Anthropic content: role is undef' );
    is( $content, undef, 'empty Anthropic content: content is undef' );
}

# ---- Unicode 中文内容 --------------------------------------------------------
{
    my $json = JSON::PP->new->utf8->encode({
        choices => [{ message => { role => 'assistant', content => '你好世界' } }]
    });
    my ($role, $content) = parse_response($json);
    is( $content, '你好世界', 'Unicode content correctly decoded' );
}

done_testing();
