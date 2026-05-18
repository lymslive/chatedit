#!/usr/bin/env perl
# 测试 decode_to_md 函数：JSON 请求体 → Markdown 对话段
use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use JSON::PP;

require "$Bin/../ai-chat.pl";

# 辅助：捕获 decode_to_md 输出到字符串（重定向 STDIN，不传参数）
sub capture_decode {
    my ($json_str) = @_;
    my $output = '';
    local @ARGV = ();
    open(local *STDIN,  '<:raw', \$json_str) or die "Cannot redirect STDIN: $!";
    open(local *STDOUT, '>',     \$output)   or die "Cannot redirect STDOUT: $!";
    decode_to_md();
    return $output;
}

# ---- 基本 user/assistant 对话 ------------------------------------------------
{
    my $json = JSON::PP->new->utf8->encode({
        model    => 'test-model',
        messages => [
            { role => 'user',      content => 'Hello' },
            { role => 'assistant', content => 'Hi there' },
        ]
    });
    my $output = capture_decode($json);
    like( $output, qr/## user >>/,      'decode: user heading present' );
    like( $output, qr/Hello/,            'decode: user content present' );
    like( $output, qr/## assistant >>/, 'decode: assistant heading present' );
    like( $output, qr/Hi there/,         'decode: assistant content present' );
}

# ---- system 消息 -------------------------------------------------------------
{
    my $json = JSON::PP->new->utf8->encode({
        messages => [
            { role => 'system', content => 'You are helpful.' },
            { role => 'user',   content => 'Hello' },
        ]
    });
    my $output = capture_decode($json);
    like( $output, qr/## system >>/,       'decode: system heading present' );
    like( $output, qr/You are helpful\./,  'decode: system content present' );
}

# ---- 消息顺序保留 -------------------------------------------------------------
{
    my $json = JSON::PP->new->utf8->encode({
        messages => [
            { role => 'user',      content => 'First' },
            { role => 'assistant', content => 'Second' },
            { role => 'user',      content => 'Third' },
        ]
    });
    my $output = capture_decode($json);
    my @sections = split /\n\n/, $output;
    ok( (grep { /## user >>/ } @sections) >= 2,      'decode: two user headings' );
    ok( (grep { /## assistant >>/ } @sections) >= 1, 'decode: one assistant heading' );
    # 顺序：user 出现在 assistant 之前
    my $user_pos  = index($output, '## user >>');
    my $asst_pos  = index($output, '## assistant >>');
    ok( $user_pos < $asst_pos, 'decode: user appears before assistant in output' );
}

# ---- 空 messages 数组 --------------------------------------------------------
{
    my $json = JSON::PP->new->utf8->encode({ messages => [] });
    my $output = capture_decode($json);
    is( $output, '', 'decode: empty messages produces empty output' );
}

done_testing();
