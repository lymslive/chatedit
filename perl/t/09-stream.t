#!/usr/bin/env perl
# 流式响应测试：_extract_stream_delta 解析 + --stream 选项行为
use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use JSON::PP;

require "$Bin/../ai-chat.pl";

# ---- _extract_stream_delta：OpenAI 格式 ----------------------------------------
{
    my $role = 'assistant';
    my $chunk = {
        choices => [{ delta => { content => 'Hello' } }]
    };
    my $text = main::_extract_stream_delta($chunk, \$role);
    is( $text, 'Hello', 'OpenAI delta: content extracted' );
    is( $role, 'assistant', 'OpenAI delta: role unchanged' );
}

{
    # 第一个 chunk 携带 role 字段（OpenAI 常见）
    my $role = 'assistant';
    my $chunk = {
        choices => [{ delta => { role => 'assistant', content => '' } }]
    };
    my $text = main::_extract_stream_delta($chunk, \$role);
    is( $text, '', 'OpenAI delta: empty content' );
    is( $role, 'assistant', 'OpenAI delta: role set from chunk' );
}

{
    # OpenAI 中文内容
    my $role = 'assistant';
    my $chunk = {
        choices => [{ delta => { content => '你好' } }]
    };
    my $text = main::_extract_stream_delta($chunk, \$role);
    is( $text, '你好', 'OpenAI delta: Unicode content' );
}

# ---- _extract_stream_delta：Anthropic 原生格式 ----------------------------------
{
    my $role = 'assistant';
    my $chunk = {
        type  => 'content_block_delta',
        index => 0,
        delta => { type => 'text_delta', text => 'World' },
    };
    my $text = main::_extract_stream_delta($chunk, \$role);
    is( $text, 'World', 'Anthropic delta: text extracted' );
}

{
    # Anthropic message_start：更新 role
    my $role = 'unknown';
    my $chunk = {
        type    => 'message_start',
        message => { role => 'assistant', id => 'msg_abc' },
    };
    my $text = main::_extract_stream_delta($chunk, \$role);
    is( $text, '',          'Anthropic message_start: no text' );
    is( $role, 'assistant', 'Anthropic message_start: role updated' );
}

{
    # Anthropic content_block_start：无文本
    my $role = 'assistant';
    my $chunk = {
        type          => 'content_block_start',
        index         => 0,
        content_block => { type => 'text', text => '' },
    };
    my $text = main::_extract_stream_delta($chunk, \$role);
    is( $text, '', 'Anthropic content_block_start: no delta text' );
}

{
    # 未知 chunk 类型：忽略
    my $role = 'assistant';
    my $chunk = { type => 'ping' };
    my $text = main::_extract_stream_delta($chunk, \$role);
    is( $text, '', 'unknown chunk type: returns empty' );
}

# ---- --stream 选项在 --encode 模式下将 stream:true 写入 JSON ----------------------
{
    my $script = "$Bin/../ai-chat.pl";
    my $md     = "## user >> Hello\n";
    my $json_out = do {
        local $ENV{API_MODEL} = 'test-model';
        # 避免脚本去查找 env 文件（覆盖 HOME，避免读真实配置）
        local $ENV{HOME} = '/tmp';
        open my $fh, '-|', $^X, $script, '--stream', '--encode', '--system', ''
            or die "无法执行脚本: $!";
        print {$fh} $md if 0;   # 占位，实际用 STDIN 注入
        close $fh;
        # 改用 pipe + fork
        undef;
    };

    # 通过 open3 / 子进程拼接 STDIN 更可靠
    use IPC::Open2;
    my ($child_out, $child_in);
    my $pid = open2($child_out, $child_in,
        $^X, $script, '--stream', '--encode', '--system', '');
    print $child_in "## user >> Hello\n";
    close $child_in;
    local $/;
    my $out = <$child_out>;
    close $child_out;
    waitpid $pid, 0;

    my $data = eval { JSON::PP->new->utf8->decode($out) };
    ok( !$@, '--stream --encode: output is valid JSON' );
    ok( $data->{stream}, '--stream --encode: stream field is true' );
    is( ref($data->{messages}), 'ARRAY', '--stream --encode: messages array present' );
}

# ---- 模板中 "stream":true 自动检测 --------------------------------------------
{
    use IPC::Open2;
    # 写一个含 stream:true 的 json 模板到临时文件
    use File::Temp qw(tempfile tempdir);
    my $tmpdir = tempdir(CLEANUP => 1);
    my $tpl_file = "$tmpdir/test.json";
    open my $tfh, '>', $tpl_file or die $!;
    print $tfh '{"model":"$API_MODEL","stream":true,"messages":[]}';
    close $tfh;

    my $script = "$Bin/../ai-chat.pl";
    my ($child_out, $child_in);
    my $pid = open2($child_out, $child_in,
        $^X, $script, '--template', $tpl_file, '--encode', '--system', '');
    print $child_in "## user >> Test\n";
    close $child_in;
    local $/;
    my $out = <$child_out>;
    close $child_out;
    waitpid $pid, 0;

    my $data = eval { JSON::PP->new->utf8->decode($out) };
    ok( !$@, 'template stream:true: output is valid JSON' );
    ok( $data->{stream}, 'template stream:true: stream field preserved' );
}

done_testing();
