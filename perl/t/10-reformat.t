#!/usr/bin/env perl
# 测试 --reformat 选项：修正 AI 回复标题等级 + 添加 ## role >> 标题行
use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use File::Temp qw(tempfile);

require "$Bin/../ai-chat.pl";

# 抑止 system 文件自动查找（opt_system = '' 表示已指定，不再自动搜索）
{
    no warnings 'once';
    $main::opt_system = '';
}

# ============================================================================
# fix_heading_level：纯文本变换函数（列表上下文返回 ($content, $count)）
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

# 无空格的 # 也视为标题（流式 delta 可能只输出 ## 等片段）
is(fix_heading_level("#标签"),        "###标签",        '#无空格也视为标题');
is(fix_heading_level("##标签"),       "###标签",        '##无空格也视为标题');

# 普通正文不受影响
is(fix_heading_level("普通文字"),     "普通文字",       '普通行不变');
is(fix_heading_level("    缩进行"),   "    缩进行",     '缩进行不变');

# 多行内容：混合标题与正文
{
    my $input = "## 背景\n\n介绍文字。\n\n### 细节\n\n更多内容。\n\n# 总结";
    my $want  = "### 背景\n\n介绍文字。\n\n#### 细节\n\n更多内容。\n\n### 总结";
    is(fix_heading_level($input), $want, '多行混合内容');
}

# 列表上下文：返回 ($content, $reformed_count)
{
    my ($out, $cnt) = fix_heading_level("## A\n\n普通行\n\n### B");
    is($out, "### A\n\n普通行\n\n#### B", '列表上下文：内容正确');
    is($cnt, 2, '列表上下文：reformatted count = 2');
}

{
    my ($out, $cnt) = fix_heading_level("普通行\n另一行");
    is($cnt, 0, '列表上下文：无标题时 count = 0');
}

# ============================================================================
# append_to_file：写文件时默认 reformat=1（undef 视为 1）
# ============================================================================

# undef → 默认行为：写文件时修正
{
    no warnings 'once';
    $main::opt_reformat = undef;
}
{
    my ($tmp_fh, $tmp_file) = tempfile(SUFFIX => '.md', UNLINK => 1);
    print $tmp_fh "## user >>\n\n问题\n";
    close $tmp_fh;

    my ($lines, $reformed) = append_to_file($tmp_file, 'assistant', "## 背景\n\n内容\n\n### 细节");

    open my $rfh, '<:utf8', $tmp_file or die $!;
    local $/;
    my $written = <$rfh>;
    close $rfh;

    like($written,   qr/### 背景/,   'append_to_file(undef): h2 → h3 写入文件');
    like($written,   qr/#### 细节/,  'append_to_file(undef): h3 → h4 写入文件');
    unlike($written, qr/^## 背景/m,  'append_to_file(undef): 原 h2 不再出现');
    like($written,   qr/## assistant >>/, 'append_to_file(undef): 标题行写入');
    ok($reformed > 0, 'append_to_file(undef): reformed_count > 0');
    ok($lines > 0,    'append_to_file(undef): lines_appended > 0');
}

# --reformat 0 显式禁止修正（写文件也不修正）
{
    no warnings 'once';
    $main::opt_reformat = 0;
}
{
    my ($tmp_fh, $tmp_file) = tempfile(SUFFIX => '.md', UNLINK => 1);
    print $tmp_fh "## user >>\n\n问题\n";
    close $tmp_fh;

    my ($lines, $reformed) = append_to_file($tmp_file, 'assistant', "## 背景\n\n内容");

    open my $rfh, '<:utf8', $tmp_file or die $!;
    local $/;
    my $written = <$rfh>;
    close $rfh;

    like($written,   qr/## 背景/, 'append_to_file(0): reformat=0 时 h2 不变');
    unlike($written, qr/## assistant >>/, 'append_to_file(0): 无标题行');
    is($reformed, 0, 'append_to_file(0): reformed_count = 0');
}

# --reformat 1 显式开启修正（与默认相同）
{
    no warnings 'once';
    $main::opt_reformat = 1;
}
{
    my ($tmp_fh, $tmp_file) = tempfile(SUFFIX => '.md', UNLINK => 1);
    print $tmp_fh "## user >>\n\n问题\n";
    close $tmp_fh;

    my ($lines, $reformed) = append_to_file($tmp_file, 'assistant', "## 背景\n\n内容");

    open my $rfh, '<:utf8', $tmp_file or die $!;
    local $/;
    my $written = <$rfh>;
    close $rfh;

    like($written, qr/### 背景/, 'append_to_file(1): reformat=1 时 h2 → h3');
    like($written, qr/## assistant >>/, 'append_to_file(1): 标题行写入');
    is($reformed, 1, 'append_to_file(1): reformed_count = 1');
}

# ============================================================================
# print_response：stdout 时默认 reformat=0（undef 视为 0）
# 用 ASCII 内容避免内存句柄的 UTF-8 字节 vs 字符匹配问题
# ============================================================================

# undef → 默认行为：stdout 不修正，无标题行
{
    no warnings 'once';
    $main::opt_reformat = undef;
}
{
    my $output = '';
    open my $fh, '>', \$output or die $!;
    print_response($fh, 'assistant', "## Section\n\nBody");
    close $fh;

    like($output,   qr/## Section/, 'print_response(undef,for_file=0): stdout 默认不修正 h2');
    unlike($output, qr/## assistant >>/, 'print_response(undef,for_file=0): 无标题行');
}

# for_file=1 时默认 reformat=1
{
    no warnings 'once';
    $main::opt_reformat = undef;
}
{
    my $output = '';
    open my $fh, '>', \$output or die $!;
    print_response($fh, 'assistant', "## Section\n\nBody", 1);
    close $fh;

    like($output, qr/### Section/,      'print_response(undef,for_file=1): h2 → h3');
    like($output, qr/## assistant >>/, 'print_response(undef,for_file=1): 有标题行');
}

# --reformat 1 显式开启：stdout 也修正
{
    no warnings 'once';
    $main::opt_reformat = 1;
}
{
    my $output = '';
    open my $fh, '>', \$output or die $!;
    print_response($fh, 'assistant', "## Section\n\nBody");
    close $fh;

    like($output, qr/### Section/,      'print_response(1): reformat=1 时 h2 → h3');
    like($output, qr/## assistant >>/, 'print_response(1): 有标题行');
}

# --reformat 0 显式禁止：stdout 不修正
{
    no warnings 'once';
    $main::opt_reformat = 0;
}
{
    my $output = '';
    open my $fh, '>', \$output or die $!;
    print_response($fh, 'assistant', "## Section\n\nBody");
    close $fh;

    like($output,   qr/## Section/, 'print_response(0): reformat=0 时 h2 不变');
    unlike($output, qr/## assistant >>/, 'print_response(0): 无标题行');
}

# ============================================================================
# append_to_file：末尾换行补充逻辑
# ============================================================================

# 文件末尾是非空行（无尾随空行）→ 追加前自动补一个空行分隔
{
    no warnings 'once';
    $main::opt_reformat = undef;
}
{
    my ($tmp_fh, $tmp_file) = tempfile(SUFFIX => '.md', UNLINK => 1);
    # 文件末尾写非空内容行（以 \n 结尾但无额外空行）
    print $tmp_fh "## user >>\n\ncontent-line\n";
    close $tmp_fh;

    append_to_file($tmp_file, 'assistant', "reply");

    open my $rfh, '<:utf8', $tmp_file or die $!;
    local $/;
    my $written = <$rfh>;
    close $rfh;

    # 追加部分应以 \n\n 与原有内容分隔（原末尾 \n + 补充的 \n）
    like($written, qr/content-line\n\n/, 'append_to_file: 末尾非空行时自动补空行分隔');
}

# 文件末尾已有空白行 → 始终补一个换行（简化逻辑，用户可自行删除多余空行）
{
    no warnings 'once';
    $main::opt_reformat = undef;
}
{
    my ($tmp_fh, $tmp_file) = tempfile(SUFFIX => '.md', UNLINK => 1);
    # 文件末尾有空行（内容行 + 空行）
    print $tmp_fh "## user >>\n\ncontent-line\n\n";
    close $tmp_fh;

    append_to_file($tmp_file, 'assistant', "reply");

    open my $rfh, '<:utf8', $tmp_file or die $!;
    local $/;
    my $written = <$rfh>;
    close $rfh;

    # 始终追加一个 \n，所以原末尾 \n\n 变为 \n\n\n（由用户自行处理多余空行）
    like($written, qr/content-line\n\n\n/, 'append_to_file: 始终追加一个换行分隔');
}

done_testing();
