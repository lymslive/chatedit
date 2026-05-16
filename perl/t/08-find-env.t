#!/usr/bin/env perl
# 测试 find_env_file：配置文件按脚本名自动查找，支持软链接多实例
use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use File::Temp qw(tempdir);
use Cwd qw(cwd);

require "$Bin/../ai-chat.pl";

# 保存初始工作目录
my $orig_dir = cwd();

# 辅助：在 $dir 下创建内容为 "KEY=val\n" 的 env 文件
sub write_env_file {
    my ($path, $val) = @_;
    open my $fh, '>', $path or die "Cannot write $path: $!";
    print $fh "API_MODEL=$val\n";
    close $fh;
}

# 辅助：重置影响 find_env_file 的全局变量
sub reset_env_opts {
    no warnings 'once';
    $main::opt_env = undef;
}

# ============================================================================
# 1. --env 显式指定路径优先级最高
# ============================================================================
{
    my $tmpdir = tempdir(CLEANUP => 1);
    my $env_path = "$tmpdir/explicit.env";
    write_env_file($env_path, 'explicit-model');

    {
        no warnings 'once';
        $main::opt_env = $env_path;
    }

    my $found = find_env_file();
    is($found, $env_path, '--env explicit path: returns that path');

    reset_env_opts();
}

# --env 指向不存在的文件时，返回 undef（不存在则跳过，继续查找）
{
    {
        no warnings 'once';
        $main::opt_env = '/tmp/nonexistent-should-not-exist.env';
    }

    my $found = find_env_file();
    # 该路径不存在，find_env_file 跳过，继续查找其他候选
    # 如果没有其他匹配文件，返回 undef
    # 此处只验证不崩溃
    ok(1, '--env nonexistent: does not crash');

    reset_env_opts();
}

# ============================================================================
# 2. 当前目录下 $prog_name.env 查找
# ============================================================================
{
    my $tmpdir = tempdir(CLEANUP => 1);
    chdir($tmpdir) or die "Cannot chdir: $!";

    write_env_file("$tmpdir/my-bot.env", 'my-bot-model');

    {
        no warnings 'once';
        $main::prog_name = 'my-bot';
        $main::opt_env   = undef;
    }

    my $found = find_env_file();
    is($found, './my-bot.env', 'CWD prog_name.env: found in current dir');

    chdir($orig_dir) or die;
    {
        no warnings 'once';
        $main::prog_name = 'ai-chat';
    }
}

# ============================================================================
# 3. 当前目录下 .chatedit/$prog_name.env 查找（优先于 home .chatedit）
# ============================================================================
{
    my $tmpdir = tempdir(CLEANUP => 1);
    chdir($tmpdir) or die "Cannot chdir: $!";

    mkdir "$tmpdir/.chatedit" or die;
    write_env_file("$tmpdir/.chatedit/sub-bot.env", 'sub-bot-model');

    {
        no warnings 'once';
        $main::prog_name = 'sub-bot';
        $main::opt_env   = undef;
    }

    my $found = find_env_file();
    is($found, './.chatedit/sub-bot.env', '.chatedit/prog_name.env: found in .chatedit subdir');

    chdir($orig_dir) or die;
    {
        no warnings 'once';
        $main::prog_name = 'ai-chat';
    }
}

# ============================================================================
# 4. 回退到通用名 ai-chat.env（prog_name 不是 ai-chat 时）
# ============================================================================
{
    my $tmpdir = tempdir(CLEANUP => 1);
    chdir($tmpdir) or die "Cannot chdir: $!";

    # 只创建通用名 ai-chat.env，不创建 other-bot.env
    write_env_file("$tmpdir/ai-chat.env", 'fallback-model');

    {
        no warnings 'once';
        $main::prog_name = 'other-bot';
        $main::opt_env   = undef;
    }

    my $found = find_env_file();
    is($found, './ai-chat.env', 'fallback to ai-chat.env when prog_name not found');

    chdir($orig_dir) or die;
    {
        no warnings 'once';
        $main::prog_name = 'ai-chat';
    }
}

# ============================================================================
# 5. prog_name 匹配的文件优先于 ai-chat.env 回退
# ============================================================================
{
    my $tmpdir = tempdir(CLEANUP => 1);
    chdir($tmpdir) or die "Cannot chdir: $!";

    write_env_file("$tmpdir/priority-bot.env", 'priority-model');
    write_env_file("$tmpdir/ai-chat.env",      'fallback-model');

    {
        no warnings 'once';
        $main::prog_name = 'priority-bot';
        $main::opt_env   = undef;
    }

    my $found = find_env_file();
    is($found, './priority-bot.env', 'prog_name.env takes priority over ai-chat.env');

    chdir($orig_dir) or die;
    {
        no warnings 'once';
        $main::prog_name = 'ai-chat';
    }
}

# ============================================================================
# 6. 没有任何 env 文件时返回 undef
# ============================================================================
{
    my $tmpdir = tempdir(CLEANUP => 1);
    chdir($tmpdir) or die "Cannot chdir: $!";

    {
        no warnings 'once';
        $main::prog_name = 'no-env-bot';
        $main::opt_env   = undef;
    }

    my $found = find_env_file();
    is($found, undef, 'no env files: returns undef');

    chdir($orig_dir) or die;
    {
        no warnings 'once';
        $main::prog_name = 'ai-chat';
    }
}

# ============================================================================
# 7. load_env: 正确解析 env 文件并设置环境变量
# ============================================================================
{
    my $tmpdir = tempdir(CLEANUP => 1);
    my $env_path = "$tmpdir/load-test.env";
    open my $fh, '>', $env_path or die;
    print $fh "API_URL=https://load-test.example.com\n";
    print $fh "API_KEY=load-test-key\n";
    print $fh "API_MODEL=load-test-model\n";
    print $fh "# 注释行\n";
    print $fh "\n";
    close $fh;

    # 清除相关环境变量
    delete $ENV{API_URL};
    delete $ENV{API_KEY};
    delete $ENV{API_MODEL};

    {
        no warnings 'once';
        $main::opt_env   = $env_path;
        $main::opt_url   = '';
        $main::opt_key   = '';
        $main::opt_model = '';
    }

    load_env();

    is($ENV{API_URL},   'https://load-test.example.com', 'load_env: API_URL set');
    is($ENV{API_KEY},   'load-test-key',                  'load_env: API_KEY set');
    is($ENV{API_MODEL}, 'load-test-model',                'load_env: API_MODEL set');

    reset_env_opts();
}

# ============================================================================
# 8. 使用 testdata/ 中的实际测试文件验证（testdata 目录作为 CWD）
# ============================================================================
{
    my $testdata_dir = "$Bin/../../testdata";

    chdir($testdata_dir) or do {
        skip("testdata dir not accessible: $!", 2);
    };

    # test-prog.env 应被找到
    {
        no warnings 'once';
        $main::prog_name = 'test-prog';
        $main::opt_env   = undef;
    }

    my $found = find_env_file();
    is($found, './test-prog.env', 'testdata/test-prog.env found when CWD=testdata');

    # test-chatedit 无同名 CWD 文件，但有 ai-chat.env 回退 → 回退文件被优先找到
    {
        no warnings 'once';
        $main::prog_name = 'test-chatedit';
        $main::opt_env   = undef;
    }

    $found = find_env_file();
    is($found, './ai-chat.env', 'testdata: ai-chat.env fallback found before .chatedit subdir');

    chdir($orig_dir) or die;
    {
        no warnings 'once';
        $main::prog_name = 'ai-chat';
    }
}

done_testing();
