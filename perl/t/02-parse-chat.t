#!/usr/bin/env perl
# 测试 parse_chat 函数：Markdown 对话解析
use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use File::Temp qw(tempfile);

require "$Bin/../ai-chat.pl";

# 抑止 inject_system 自动查找 ai-chat.sys 文件（parse_chat 本身不调 inject_system，
# 但保险起见仍禁用全局选项以免影响后续流程）
{
    no warnings 'once';
    $main::opt_system       = '';
}

# 辅助：从字符串解析，返回 message 列表
sub parse_md {
    my ($text) = @_;
    open my $fh, '<:utf8', \$text or die "Cannot open string ref: $!";
    my @msgs = parse_chat($fh);
    close $fh;
    return @msgs;
}

# ---- 基本 Q/A 缩写角色 -------------------------------------------------------
{
    my @msgs = parse_md("## Q >> Hello\n\n## A >> Hi there\n");
    is( scalar @msgs,      2,           'Q/A: 2 messages parsed' );
    is( $msgs[0]{role},    'user',      'Q -> user' );
    is( $msgs[0]{content}, 'Hello',     'user content correct' );
    is( $msgs[1]{role},    'assistant', 'A -> assistant' );
    is( $msgs[1]{content}, 'Hi there',  'assistant content correct' );
}

# ---- 完整角色名 ---------------------------------------------------------------
{
    my @msgs = parse_md("## user >> Question\n\n## assistant >> Answer\n");
    is( $msgs[0]{role}, 'user',      'full role: user' );
    is( $msgs[1]{role}, 'assistant', 'full role: assistant' );
}

# ---- system 角色 -------------------------------------------------------------
{
    my @msgs = parse_md("## system >> Be helpful\n\n## user >> Hello\n");
    is( scalar @msgs,      2,           'system + user: 2 messages' );
    is( $msgs[0]{role},    'system',    'system role' );
    is( $msgs[0]{content}, 'Be helpful','system content' );
}

# ---- >> 后行内文本 + 多行内容 -------------------------------------------------
{
    my @msgs = parse_md("## Q >> First line\nSecond line\nThird line\n\n## A >> Response\n");
    is( $msgs[0]{content}, "First line\nSecond line\nThird line", 'multiline content preserved' );
}

# ---- P/system 缩写 -----------------------------------------------------------
{
    my @msgs = parse_md("## P >> System prompt\n\n## Q >> Hello\n");
    is( $msgs[0]{role},    'system',       'P -> system' );
    is( $msgs[0]{content}, 'System prompt','P content' );
}

# ---- 注释行（# 前缀）不进入消息，且结束当前段 --------------------------------
{
    my @msgs = parse_md("# top-level comment\n\n## Q >> Hello\n\n# end comment\n");
    is( scalar @msgs,      1,       '# comment: only 1 message' );
    is( $msgs[0]{content}, 'Hello', 'comment ends segment' );
}

# ---- ## 非角色标题结束段 ------------------------------------------------------
{
    my @msgs = parse_md("## Q >> Hello\n\n## Not a role heading\n\n## A >> Hi\n");
    is( scalar @msgs, 2, 'non-role ## ends segment, 2 messages' );
}

# ---- ### 子标题在段内为普通内容 -----------------------------------------------
{
    my @msgs = parse_md("## Q >> Hello\n### Sub-section\nContent below\n\n## A >> Hi\n");
    is( scalar @msgs,      2,                                       '### does not split messages' );
    is( $msgs[0]{content}, "Hello\n### Sub-section\nContent below", '### treated as content' );
}

# ---- 代码块内的 ## 不作分隔符 ------------------------------------------------
{
    my $md = "## Q >> Ask\n```\n## fake-role >> should not parse\n```\nafter block\n\n## A >> Answer\n";
    my @msgs = parse_md($md);
    is( scalar @msgs,      2,                              'code block: 2 messages' );
    ok( $msgs[0]{content} =~ /fake-role/,                  'code block content preserved verbatim' );
    ok( $msgs[0]{content} =~ /after block/,                'content after code block included' );
}

# ---- @file 文件引入 -----------------------------------------------------------
{
    my ($tmp_fh, $tmp_file) = tempfile( SUFFIX => '.txt', UNLINK => 1 );
    print $tmp_fh "included content\n";
    close $tmp_fh;

    # @file 必须独占一行（不能放在 >> 同行），才会被展开
    my @msgs = parse_md("## Q >>\n\@$tmp_file\n");
    is( $msgs[0]{content}, 'included content', '@file: content included correctly' );
}

# ---- @file 不存在 → (Read Error) ---------------------------------------------
{
    # 静默 STDERR 警告
    open my $old_err, '>&', \*STDERR or die $!;
    open STDERR, '>', '/dev/null' or die $!;
    my @msgs = parse_md("## Q >>\n\@/nonexistent/__no_such_file__.txt\n");
    open STDERR, '>&', $old_err or die $!;

    like( $msgs[0]{content}, qr/Read Error/, '@missing file: (Read Error) appended' );
}

# ---- !cmd 命令输出 ------------------------------------------------------------
{
    # !cmd 同样需独占一行
    my @msgs = parse_md("## Q >>\n!echo hello\n");
    is( $msgs[0]{content}, 'hello', '!cmd: output captured' );
}

# ---- !cmd 失败 → (Read Error) ------------------------------------------------
{
    open my $old_err, '>&', \*STDERR or die $!;
    open STDERR, '>', '/dev/null' or die $!;
    my @msgs = parse_md("## Q >>\n!exit 1\n");
    open STDERR, '>&', $old_err or die $!;

    like( $msgs[0]{content}, qr/Read Error/, '!failing cmd: (Read Error) appended' );
}

# ---- 尾部多余空行被去掉 -------------------------------------------------------
{
    my @msgs = parse_md("## Q >> Hello\n\n\n\n");
    is( $msgs[0]{content}, 'Hello', 'trailing blank lines stripped from content' );
}

# ---- 空文件 ------------------------------------------------------------------
{
    my @msgs = parse_md("");
    is( scalar @msgs, 0, 'empty input: no messages' );
}

done_testing();
