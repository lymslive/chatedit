#!/usr/bin/env perl
# 测试 inject_system：系统提示注入逻辑
#   - $opt_system 为字符串值时直接注入
#   - $opt_system 为 @file 引用时读文件注入
#   - $opt_system 为 '' 或 '0' 时抑止注入
#   - $opt_system 为 undef 时走自动搜索路径
#   - 已有 system 消息时不重复插入
use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use File::Temp qw(tempfile);

require "$Bin/../ai-chat.pl";

# ============================================================================
# 基础设置：抑止自动搜索（避免干扰）
# ============================================================================
{
    no warnings 'once';
    $main::opt_system = '';
}

# ============================================================================
# 场景 1：$opt_system 为直接字符串 → 注入为第一条 system 消息
# ============================================================================
{
    no warnings 'once';
    $main::opt_system = 'Be concise and helpful.';
}
{
    my @messages = ( { role => 'user', content => 'Hi' } );
    inject_system(\@messages);

    is( scalar @messages,        2,                        'direct string: prepends 1 message' );
    is( $messages[0]{role},      'system',                 'direct string: first role = system' );
    is( $messages[0]{content},   'Be concise and helpful.', 'direct string: content matches' );
    is( $messages[1]{role},      'user',                   'direct string: user message preserved' );
}

# ============================================================================
# 场景 2：$opt_system 为 @filepath → 读取文件内容注入
# ============================================================================
{
    my ($tmp_fh, $tmp_file) = tempfile(SUFFIX => '.txt', UNLINK => 1);
    print $tmp_fh "System prompt from file\n";
    close $tmp_fh;

    {
        no warnings 'once';
        $main::opt_system = "\@$tmp_file";
    }

    my @messages = ( { role => 'user', content => 'Test' } );
    inject_system(\@messages);

    is( scalar @messages,      2,                       '@file: prepends system message' );
    is( $messages[0]{role},    'system',                '@file: role = system' );
    is( $messages[0]{content}, 'System prompt from file', '@file: content from file' );
}

# ============================================================================
# 场景 3：$opt_system = '' → 抑止注入
# ============================================================================
{
    no warnings 'once';
    $main::opt_system = '';
}
{
    my @messages = ( { role => 'user', content => 'Hi' } );
    inject_system(\@messages);

    is( scalar @messages,   1,      'empty string: no prepend' );
    is( $messages[0]{role}, 'user', 'empty string: first message unchanged' );
}

# ============================================================================
# 场景 4：$opt_system = '0' → 抑止注入
# ============================================================================
{
    no warnings 'once';
    $main::opt_system = '0';
}
{
    my @messages = ( { role => 'user', content => 'Hi' } );
    inject_system(\@messages);

    is( scalar @messages,   1,      '"0": no prepend' );
    is( $messages[0]{role}, 'user', '"0": first message unchanged' );
}

# ============================================================================
# 场景 5：$opt_system = undef + find_system_file 返回 undef → 不注入
# ============================================================================
{
    no warnings 'once';
    $main::opt_system = undef;

    no warnings 'redefine';
    local *main::find_system_file = sub { return undef };

    my @messages = ( { role => 'user', content => 'Hi' } );
    inject_system(\@messages);

    is( scalar @messages,   1,      'undef+no file: no prepend' );
    is( $messages[0]{role}, 'user', 'undef+no file: first message unchanged' );
}

# ============================================================================
# 场景 6：$opt_system = undef + find_system_file 返回文件路径 → 读文件注入
# ============================================================================
{
    my ($tmp_fh, $tmp_file) = tempfile(SUFFIX => '.sys', UNLINK => 1);
    print $tmp_fh "Auto-loaded system prompt\n";
    close $tmp_fh;

    no warnings 'once';
    $main::opt_system = undef;

    no warnings 'redefine';
    local *main::find_system_file = sub { return $tmp_file };

    my @messages = ( { role => 'user', content => 'Hi' } );
    inject_system(\@messages);

    is( scalar @messages,      2,                          'undef+file: prepends system' );
    is( $messages[0]{role},    'system',                   'undef+file: role = system' );
    is( $messages[0]{content}, 'Auto-loaded system prompt', 'undef+file: content from .sys file' );
}

# ============================================================================
# 场景 7：已有 system 消息时不重复插入
# ============================================================================
{
    no warnings 'once';
    $main::opt_system = 'New system prompt';
}
{
    my @messages = (
        { role => 'system', content => 'Existing system' },
        { role => 'user',   content => 'Hi' },
    );
    inject_system(\@messages);

    is( scalar @messages,      2,                   'existing system: no duplicate prepend' );
    is( $messages[0]{role},    'system',             'existing system: first still system' );
    is( $messages[0]{content}, 'Existing system',    'existing system: original content preserved' );
}

# 恢复：抑止 system 查找，避免影响其他测试
{
    no warnings 'once';
    $main::opt_system = '';
}

done_testing();
