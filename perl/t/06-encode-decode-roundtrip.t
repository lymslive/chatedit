#!/usr/bin/env perl
# 集成测试：通过子进程调用脚本，验证 --encode / --decode 互逆
use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use File::Temp qw(tempfile);

my $script = "$Bin/../ai-chat.pl";

# 辅助：运行脚本并捕获 stdout（忽略 stderr）
sub run_script {
    my (@args) = @_;
    my $out = qx(perl "$script" @args 2>/dev/null);
    return ($?, $out);
}

# ---- --encode 基本功能 -------------------------------------------------------
{
    my $md_file = "$Bin/../../testdata/chat-hello.md";
    my ($exit, $json_out) = run_script("--encode", "\"$md_file\"");
    is( $exit, 0, '--encode exits 0' );

    my $data = eval { require JSON::PP; JSON::PP->new->utf8->decode($json_out) };
    ok( !$@,                                   '--encode outputs valid JSON' );
    ok( exists $data->{messages},              'JSON has messages key' );
    is( ref($data->{messages}), 'ARRAY',       'messages is array' );
    ok( scalar @{ $data->{messages} } > 0,     'messages array is non-empty' );
    is( $data->{messages}[0]{role}, 'user',    'first message role is user' );
}

# ---- --decode 基本功能 -------------------------------------------------------
{
    my $json_file = "$Bin/../../testdata/chat-system.md";
    # 先 encode，再 decode，检查输出包含角色标题
    my (undef, $json_out) = run_script("--encode", "\"$json_file\"");

    my ($tmp_fh, $tmp_file) = tempfile( SUFFIX => '.json', UNLINK => 1 );
    binmode $tmp_fh, ':raw';
    print $tmp_fh $json_out;
    close $tmp_fh;

    my ($exit, $md_out) = run_script("--decode", "\"$tmp_file\"");
    is( $exit, 0,                              '--decode exits 0' );
    like( $md_out, qr/## system >>/,          '--decode outputs system heading' );
    like( $md_out, qr/## user >>/,            '--decode outputs user heading' );
    like( $md_out, qr/## assistant >>/,       '--decode outputs assistant heading' );
}

# ---- encode → decode 内容保真性 ---------------------------------------------
{
    my ($tmp_md_fh, $tmp_md) = tempfile( SUFFIX => '.md', UNLINK => 1 );
    binmode $tmp_md_fh, ':utf8';
    print $tmp_md_fh "## user >> Round-trip test message\n\n## assistant >> This is the reply.\n";
    close $tmp_md_fh;

    my (undef, $json_out)  = run_script("--encode", "\"$tmp_md\"");
    my ($tmp_json_fh, $tmp_json) = tempfile( SUFFIX => '.json', UNLINK => 1 );
    binmode $tmp_json_fh, ':raw';
    print $tmp_json_fh $json_out;
    close $tmp_json_fh;

    my (undef, $md_out) = run_script("--decode", "\"$tmp_json\"");
    like( $md_out, qr/Round-trip test message/, 'round-trip: user content preserved' );
    like( $md_out, qr/This is the reply\./,      'round-trip: assistant content preserved' );
}

# ---- --encode 对中文内容无损 -------------------------------------------------
{
    my ($tmp_fh, $tmp_file) = tempfile( SUFFIX => '.md', UNLINK => 1 );
    binmode $tmp_fh, ':utf8';
    print $tmp_fh "## Q >> 你好，请介绍一下自己\n\n## A >> 我是 AI 助手。\n";
    close $tmp_fh;

    my ($exit, $json_out) = run_script("--encode", "\"$tmp_file\"");
    is( $exit, 0,                       '--encode Chinese: exits 0' );

    require JSON::PP;
    my $data = JSON::PP->new->utf8->decode($json_out);
    like( $data->{messages}[0]{content}, qr/你好/, '--encode Chinese: content preserved' );
}

# ---- 重复迭代内容稳定性（encode→decode→encode 幂等）--------------------------
# 第一次 encode→decode 允许少量格式整理（去除多余空行等），
# 但从第二次迭代起 JSON messages 内容必须完全相同。
{
    require JSON::PP;

    my ($md_fh, $md_file) = tempfile( SUFFIX => '.md', UNLINK => 1 );
    binmode $md_fh, ':utf8';
    # 包含多余空行、不同行末格式，模拟真实用户编辑文件
    print $md_fh "## user >> Hello\n\nMultiline body.\n\n## assistant >> Response here.\n\n";
    close $md_fh;

    # 第 1 次 encode
    my (undef, $json1) = run_script("--encode", "\"$md_file\"");
    my ($j1_fh, $j1_file) = tempfile( SUFFIX => '.json', UNLINK => 1 );
    binmode $j1_fh, ':raw'; print $j1_fh $json1; close $j1_fh;

    # decode → md2
    my (undef, $md2) = run_script("--decode", "\"$j1_file\"");
    my ($md2_fh, $md2_file) = tempfile( SUFFIX => '.md', UNLINK => 1 );
    binmode $md2_fh, ':utf8'; print $md2_fh $md2; close $md2_fh;

    # 第 2 次 encode（从 decode 输出再 encode）
    my (undef, $json2) = run_script("--encode", "\"$md2_file\"");
    my ($j2_fh, $j2_file) = tempfile( SUFFIX => '.json', UNLINK => 1 );
    binmode $j2_fh, ':raw'; print $j2_fh $json2; close $j2_fh;

    # 第 2 次 decode
    my (undef, $md3) = run_script("--decode", "\"$j2_file\"");

    # 比较两次 JSON 的 messages 内容（而非 model 字段，那可能含占位符）
    my $data1 = JSON::PP->new->utf8->decode($json1);
    my $data2 = JSON::PP->new->utf8->decode($json2);
    my $msgs1 = $data1->{messages};
    my $msgs2 = $data2->{messages};

    is( scalar @$msgs2, scalar @$msgs1, 'idempotent: message count unchanged after 2nd encode' );
    for my $i (0 .. $#$msgs1) {
        is( $msgs2->[$i]{role},    $msgs1->[$i]{role},    "idempotent: msg[$i] role stable" );
        is( $msgs2->[$i]{content}, $msgs1->[$i]{content}, "idempotent: msg[$i] content stable" );
    }

    # decode 输出也稳定：md2 与 md3 完全相同
    is( $md3, $md2, 'idempotent: decode output stable on 2nd iteration' );
}

done_testing();
