#!/usr/bin/env perl
# 测试 --fix-level 选项：修正 AI 回复中的 Markdown 标题等级
use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use File::Temp qw(tempfile);

require "$Bin/../ai-chat.pl";

# 抑止 system 文件自动查找
{
    no warnings 'once';
    $main::opt_system_given = 1;
    $main::opt_system       = '';
}

# ============================================================================
# fix_heading_level：纯文本变换函数（不检查全局 opt_fix_level）
# ============================================================================

# h1 → h3（前置两个 #）
is(fix_heading_level("# 一级标题"),   "### 一级标题",   'h1 → h3');
is(fix_heading_level("# Title"),      "### Title",      'h1 → h3 (ASCII)');

# h2 → h3（前置一个 #）
is(fix_heading_level("## 二级标题"),  "### 二级标题",   'h2 → h3');
is(fix_heading_level("## Section"),   "### Section",    'h2 → h3 (ASCII)');

# h3 → h4
is(fix_heading_level("### 三级"),     "#### 三级",      'h3 → h4');

# h4 → h5
is(fix_heading_level("#### 四级"),    "##### 四级",     'h4 → h5');

# 非标题行（无空格）不受影响
is(fix_heading_level("#标签"),        "#标签",          '#无空格不视为标题');
is(fix_heading_level("##标签"),       "##标签",         '##无空格不视为标题');

# 普通正文不受影响
is(fix_heading_level("普通文字"),     "普通文字",       '普通行不变');
is(fix_heading_level("    缩进行"),   "    缩进行",     '缩进行不变');

# 多行内容：混合标题与正文
{
    my $input = "## 背景\n\n介绍文字。\n\n### 细节\n\n更多内容。\n\n# 总结";
    my $want  = "### 背景\n\n介绍文字。\n\n#### 细节\n\n更多内容。\n\n### 总结";
    is(fix_heading_level($input), $want, '多行混合内容');
}

# ============================================================================
# append_to_file：写文件时默认 fix_level=1（undef 视为 1）
# ============================================================================

# undef → 默认行为：写文件时修正
{
    no warnings 'once';
    $main::opt_fix_level = undef;
}
{
    my ($tmp_fh, $tmp_file) = tempfile(SUFFIX => '.md', UNLINK => 1);
    print $tmp_fh "## user >>\n\n问题\n";
    close $tmp_fh;

    append_to_file($tmp_file, 'assistant', "## 背景\n\n内容\n\n### 细节");

    open my $rfh, '<:utf8', $tmp_file or die $!;
    local $/;
    my $written = <$rfh>;
    close $rfh;

    like($written,   qr/### 背景/,   'append_to_file(undef): h2 → h3 写入文件');
    like($written,   qr/#### 细节/,  'append_to_file(undef): h3 → h4 写入文件');
    unlike($written, qr/^## 背景/m,  'append_to_file(undef): 原 h2 不再出现');
}

# --fix-level 0 显式禁止修正（写文件也不修正）
{
    no warnings 'once';
    $main::opt_fix_level = 0;
}
{
    my ($tmp_fh, $tmp_file) = tempfile(SUFFIX => '.md', UNLINK => 1);
    print $tmp_fh "## user >>\n\n问题\n";
    close $tmp_fh;

    append_to_file($tmp_file, 'assistant', "## 背景\n\n内容");

    open my $rfh, '<:utf8', $tmp_file or die $!;
    local $/;
    my $written = <$rfh>;
    close $rfh;

    like($written, qr/## 背景/, 'append_to_file(0): fix_level=0 时 h2 不变');
}

# --fix-level 1 显式开启修正（与默认相同）
{
    no warnings 'once';
    $main::opt_fix_level = 1;
}
{
    my ($tmp_fh, $tmp_file) = tempfile(SUFFIX => '.md', UNLINK => 1);
    print $tmp_fh "## user >>\n\n问题\n";
    close $tmp_fh;

    append_to_file($tmp_file, 'assistant', "## 背景\n\n内容");

    open my $rfh, '<:utf8', $tmp_file or die $!;
    local $/;
    my $written = <$rfh>;
    close $rfh;

    like($written, qr/### 背景/, 'append_to_file(1): fix_level=1 时 h2 → h3');
}

# ============================================================================
# print_response：标准输出时默认 fix_level=0（undef 视为 0）
# 用 ASCII 内容避免内存句柄的 UTF-8 字节 vs 字符匹配问题
# ============================================================================
{
    no warnings 'once';
    $main::opt_header    = 0;
}

# undef → 默认行为：stdout 不修正
{
    no warnings 'once';
    $main::opt_fix_level = undef;
}
{
    my $output = '';
    open my $fh, '>', \$output or die $!;
    print_response($fh, 'assistant', "## Section\n\nBody");
    close $fh;

    like($output, qr/## Section/, 'print_response(undef): stdout 默认不修正 h2');
}

# --fix-level 1 显式开启：stdout 也修正
{
    no warnings 'once';
    $main::opt_fix_level = 1;
}
{
    my $output = '';
    open my $fh, '>', \$output or die $!;
    print_response($fh, 'assistant', "## Section\n\nBody");
    close $fh;

    like($output, qr/### Section/, 'print_response(1): fix_level=1 时 h2 → h3');
}

# --fix-level 0 显式禁止：stdout 不修正
{
    no warnings 'once';
    $main::opt_fix_level = 0;
}
{
    my $output = '';
    open my $fh, '>', \$output or die $!;
    print_response($fh, 'assistant', "## Section\n\nBody");
    close $fh;

    like($output, qr/## Section/, 'print_response(0): fix_level=0 时 h2 不变');
}

done_testing();
