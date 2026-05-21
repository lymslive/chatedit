#!/usr/bin/env perl
# 测试 _process_stream_lines：SSE 流主循环处理（内容累积、stdout 输出、reformat）
use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);

require "$Bin/../ai-chat.pl";

# 抑止 system 文件自动查找
{ no warnings 'once'; $main::opt_system = ''; }

# ----------------------------------------------------------------------------
# 辅助：将 SSE 文本包装为可读文件句柄
# ----------------------------------------------------------------------------
sub sse_fh
{
    my ($text) = @_;
    open my $fh, '<', \$text or die "open scalar ref: $!";
    return $fh;
}

# 辅助：调用 _process_stream_lines，同时捕获其 STDOUT 输出
# 返回 ($stdout_captured, $role, $content)
sub capture_stream_lines
{
    my ($sse_text, $reformat) = @_;
    my $fh = sse_fh($sse_text);
    my $captured = '';
    {
        local *STDOUT;
        open STDOUT, '>:utf8', \$captured or die "open STDOUT: $!";
        my ($role, $content) = main::_process_stream_lines($fh, $reformat);
        close STDOUT;
        return ($captured, $role, $content);
    }
}

# ============================================================================
# OpenAI 格式 – reformat=0（原样输出，不加标题行，不修正标题等级）
# ============================================================================
{
    my $sse = join('',
        "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\",\"content\":\"\"},\"finish_reason\":null}]}\n",
        "\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\"Hello \"},\"finish_reason\":null}]}\n",
        "\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\"world\\n\"},\"finish_reason\":null}]}\n",
        "\n",
        "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n",
        "\n",
        "data: [DONE]\n",
    );

    my ($out, $role, $content) = capture_stream_lines($sse, 0);
    is($role,    'assistant',    'OpenAI reformat=0: role correct');
    is($content, "Hello world\n", 'OpenAI reformat=0: content accumulated');
    is($out,     "Hello world\n", 'OpenAI reformat=0: stdout raw');
}

# ============================================================================
# OpenAI 格式 – reformat=1（加标题行，修正标题等级）
# ============================================================================
{
    my $sse = join('',
        "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\",\"content\":\"\"},\"finish_reason\":null}]}\n",
        "\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\"## Section\\n\"},\"finish_reason\":null}]}\n",
        "\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\"body\\n\"},\"finish_reason\":null}]}\n",
        "\n",
        "data: [DONE]\n",
    );

    my ($out, $role, $content) = capture_stream_lines($sse, 1);
    is($role,    'assistant',              'OpenAI reformat=1: role correct');
    is($content, "## Section\nbody\n",     'OpenAI reformat=1: content stores original (unformatted)');
    like($out,   qr/^## assistant >>\n\n/, 'OpenAI reformat=1: header printed first');
    like($out,   qr/### Section\n/,        'OpenAI reformat=1: h2 → h3 in stdout');
    unlike($out, qr/^## Section/m,         'OpenAI reformat=1: no raw h2 in stdout');
}

# ============================================================================
# 标题出现在行中间：prev_ends_nl=0 时，首个换行后才开始修正
# ============================================================================
{
    # chunk1: "text"（无换行，prev_ends_nl=0）
    # chunk2: "\n## Heading\n"（前段在行中，不修正；换行后修正）
    my $sse = join('',
        "data: {\"choices\":[{\"delta\":{\"content\":\"text\"},\"finish_reason\":null}]}\n",
        "\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\"\\n## Heading\\n\"},\"finish_reason\":null}]}\n",
        "\n",
        "data: [DONE]\n",
    );

    my ($out, $role, $content) = capture_stream_lines($sse, 1);
    is($content, "text\n## Heading\n",  'mid-line heading: content stores original');
    like($out,   qr/### Heading\n/,     'mid-line heading: h2 → h3 after newline');
    unlike($out, qr/^## Heading\n/m,   'mid-line heading: no raw h2 in stdout');
}

# ============================================================================
# 标题出现在行首：prev_ends_nl=1 时直接修正
# ============================================================================
{
    my $sse = join('',
        "data: {\"choices\":[{\"delta\":{\"content\":\"before\\n\"},\"finish_reason\":null}]}\n",
        "\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\"## Heading\\n\"},\"finish_reason\":null}]}\n",
        "\n",
        "data: [DONE]\n",
    );

    my ($out, $role, $content) = capture_stream_lines($sse, 1);
    like($out, qr/before\n/,     'line-start heading: "before" preserved');
    like($out, qr/### Heading\n/, 'line-start heading: h2 → h3');
}

# ============================================================================
# Anthropic 原生格式
# ============================================================================
{
    my $sse = join('',
        "data: {\"type\":\"message_start\",\"message\":{\"role\":\"assistant\"}}\n",
        "\n",
        "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hi\\n\"}}\n",
        "\n",
        "data: {\"type\":\"message_stop\"}\n",
        "\n",
        "data: [DONE]\n",
    );

    my ($out, $role, $content) = capture_stream_lines($sse, 0);
    is($role,    'assistant', 'Anthropic: role from message_start');
    is($content, "Hi\n",      'Anthropic: content accumulated');
    is($out,     "Hi\n",      'Anthropic: stdout raw output');
}

# ============================================================================
# 非 data 行、空行、无效 JSON 均跳过
# ============================================================================
{
    my $sse = join('',
        "event: ping\n",
        "\n",
        "data: not-valid-json\n",
        "\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\"OK\"},\"finish_reason\":null}]}\n",
        "\n",
        "data: [DONE]\n",
    );

    my ($out, $role, $content) = capture_stream_lines($sse, 0);
    is($content, 'OK', 'skip: non-data / invalid JSON ignored');
    is($out,     'OK', 'skip: stdout only valid content');
}

# ============================================================================
# 空流（仅有 [DONE]）
# ============================================================================
{
    my $sse = "data: [DONE]\n";

    my ($out, $role, $content) = capture_stream_lines($sse, 0);
    is($role,    'assistant', 'empty stream: default role');
    is($content, '',          'empty stream: empty content');
    is($out,     '',          'empty stream: no stdout');
}

# ============================================================================
# 从 testdata 文件读取 OpenAI SSE，验证 reformat=0 结果
# ============================================================================
{
    my $sse_file = "$Bin/../../testdata/stream-openai.sse";
    open my $fh, '<', $sse_file or die "Cannot open $sse_file: $!";
    my $captured = '';
    {
        local *STDOUT;
        open STDOUT, '>:utf8', \$captured or die $!;
        my ($role, $content) = main::_process_stream_lines($fh, 0);
        close STDOUT;
        is($role, 'assistant',           'testdata OpenAI: role correct');
        like($content, qr/Hello world\n/, 'testdata OpenAI: content has Hello world');
        like($content, qr/## Section\n/,  'testdata OpenAI: content has raw ## Section');
        like($captured, qr/## Section\n/, 'testdata OpenAI reformat=0: stdout raw h2');
    }
    close $fh;
}

# ============================================================================
# 从 testdata 文件读取 Anthropic SSE，验证内容提取
# ============================================================================
{
    my $sse_file = "$Bin/../../testdata/stream-anthropic.sse";
    open my $fh, '<', $sse_file or die "Cannot open $sse_file: $!";
    my $captured = '';
    {
        local *STDOUT;
        open STDOUT, '>:utf8', \$captured or die $!;
        my ($role, $content) = main::_process_stream_lines($fh, 0);
        close STDOUT;
        is($role, 'assistant',            'testdata Anthropic: role correct');
        like($content, qr/Hello world\n/, 'testdata Anthropic: content correct');
        like($content, qr/## Section\n/,  'testdata Anthropic: heading in content');
    }
    close $fh;
}

done_testing();
