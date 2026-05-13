#!/usr/bin/env perl
# 模拟 API 响应测试：覆盖 call_api 以避免真实网络调用
#
# 模拟原理：require 加载脚本后，用符号表替换覆盖 *main::call_api，
# 返回预设的 JSON 响应体，从而测试 parse_response + 整体编码流程，
# 无需设置任何 API 密钥或网络连接。
use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use JSON::PP;

require "$Bin/../ai-chat.pl";

# 抑止 system 文件自动查找
{
    no warnings 'once';
    $main::opt_system_given = 1;
    $main::opt_system       = '';
}

# ---- 模拟 OpenAI 格式响应 ----------------------------------------------------
{
    my $mock_json = JSON::PP->new->utf8->encode({
        choices => [{ message => { role => 'assistant', content => 'Mocked answer' } }]
    });

    no warnings 'redefine';
    local *main::call_api = sub { return $mock_json };

    my $markdown = "## Q >> What is 1+1?\n";
    open my $fh, '<:utf8', \$markdown or die $!;
    my @messages = parse_chat($fh);
    close $fh;

    is( scalar @messages,   1,      'mock OpenAI: 1 message parsed' );
    is( $messages[0]{role}, 'user', 'mock OpenAI: role is user' );

    my $template     = { model => 'test', messages => \@messages };
    my $request_json = JSON::PP->new->utf8->encode($template);

    my $response_json = call_api($request_json, 'http://mock-url', 'mock-key');
    my ($role, $content) = parse_response($response_json);

    is( $role,    'assistant',    'mock OpenAI: response role' );
    is( $content, 'Mocked answer', 'mock OpenAI: response content' );
}

# ---- 模拟 Anthropic 原生格式响应 ---------------------------------------------
{
    my $mock_json = JSON::PP->new->utf8->encode({
        role    => 'assistant',
        content => [{ type => 'text', text => 'Claude says hello' }]
    });

    no warnings 'redefine';
    local *main::call_api = sub { return $mock_json };

    my $markdown = "## user >> Hello Claude\n";
    open my $fh, '<:utf8', \$markdown or die $!;
    my @messages = parse_chat($fh);
    close $fh;

    my $template     = { model => 'claude-3', messages => \@messages };
    my $request_json = JSON::PP->new->utf8->encode($template);

    my $response_json = call_api($request_json, 'http://mock-url', 'mock-key');
    my ($role, $content) = parse_response($response_json);

    is( $role,    'assistant',        'mock Anthropic: role' );
    is( $content, 'Claude says hello', 'mock Anthropic: content' );
}

# ---- 模拟 API 返回错误响应 ---------------------------------------------------
{
    my $mock_json = JSON::PP->new->utf8->encode({
        error => { type => 'auth_error', message => 'Invalid API key' }
    });

    no warnings 'redefine';
    local *main::call_api = sub { return $mock_json };

    my $response_json = call_api('{}', 'http://mock-url', 'bad-key');
    my ($role, $content) = parse_response($response_json);

    is( $role,    undef, 'mock error response: role is undef' );
    is( $content, undef, 'mock error response: content is undef' );
}

# ---- 模拟中文内容 Unicode 完整性 ---------------------------------------------
{
    my $mock_json = JSON::PP->new->utf8->encode({
        choices => [{ message => { role => 'assistant', content => '你好，这是中文回复' } }]
    });

    no warnings 'redefine';
    local *main::call_api = sub { return $mock_json };

    my $response_json = call_api('{}', 'http://mock-url', 'key');
    my ($role, $content) = parse_response($response_json);

    is( $content, '你好，这是中文回复', 'mock: Unicode content round-trips correctly' );
}

done_testing();
