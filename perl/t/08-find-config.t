#!/usr/bin/env perl
# 测试 find_config_file / load_env / load_template：配置文件按脚本名自动查找，支持软链接多实例
use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use File::Temp qw(tempdir);
use Cwd qw(cwd);

require "$Bin/../ai-chat.pl";

# 保存初始工作目录
my $orig_dir = cwd();

# 辅助：在 $path 创建内容为 "KEY=val\n" 的 env 文件
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
# 1. load_env: --env 显式指定已存在文件时正确加载
# ============================================================================
{
    my $tmpdir = tempdir(CLEANUP => 1);
    my $env_path = "$tmpdir/explicit.env";
    write_env_file($env_path, 'explicit-model');

    delete $ENV{API_MODEL};
    {
        no warnings 'once';
        $main::opt_env   = $env_path;
        $main::opt_url   = '';
        $main::opt_key   = '';
        $main::opt_model = '';
    }

    load_env();
    is($ENV{API_MODEL}, 'explicit-model', 'load_env: --env 显式文件正确加载');

    reset_env_opts();
}

# ============================================================================
# 2. load_env: --env 指向不存在的文件时，打印警告但不崩溃
# ============================================================================
{
    {
        no warnings 'once';
        $main::opt_env   = '/tmp/nonexistent-should-not-exist-aichat.env';
        $main::opt_url   = '';
        $main::opt_key   = '';
        $main::opt_model = '';
    }

    my $warned = '';
    local $SIG{__WARN__} = sub { $warned .= $_[0] };
    eval { load_env() };
    ok(!$@, 'load_env: --env 指向不存在文件不崩溃');
    like($warned, qr/警告.*不存在/, 'load_env: --env 不存在文件打印警告');

    reset_env_opts();
}

# ============================================================================
# 3. find_config_file: 当前目录下 $prog_name.env 查找
# ============================================================================
{
    my $tmpdir = tempdir(CLEANUP => 1);
    chdir($tmpdir) or die "Cannot chdir: $!";

    write_env_file("$tmpdir/my-bot.env", 'my-bot-model');

    {
        no warnings 'once';
        $main::prog_name = 'my-bot';
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
# 4. find_config_file: .chatedit/$prog_name.env 优先于 ai-chat 回退名
# ============================================================================
{
    my $tmpdir = tempdir(CLEANUP => 1);
    chdir($tmpdir) or die "Cannot chdir: $!";

    mkdir "$tmpdir/.chatedit" or die;
    write_env_file("$tmpdir/.chatedit/sub-bot.env", 'sub-bot-model');

    {
        no warnings 'once';
        $main::prog_name = 'sub-bot';
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
# 5. find_config_file: 回退到通用名 ai-chat.env（prog_name 不是 ai-chat 时）
# ============================================================================
{
    my $tmpdir = tempdir(CLEANUP => 1);
    chdir($tmpdir) or die "Cannot chdir: $!";

    # 只创建通用名 ai-chat.env，不创建 other-bot.env
    write_env_file("$tmpdir/ai-chat.env", 'fallback-model');

    {
        no warnings 'once';
        $main::prog_name = 'other-bot';
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
# 6. find_config_file: prog_name 所有目录优先于 ai-chat 回退（正确的跨目录顺序）
# ============================================================================
{
    my $tmpdir = tempdir(CLEANUP => 1);
    chdir($tmpdir) or die "Cannot chdir: $!";

    # ./ai-chat.env 存在，但 .chatedit/priority-bot.env 也存在
    # 正确顺序：先遍历 prog_name 的所有目录，再遍历 ai-chat 回退
    write_env_file("$tmpdir/ai-chat.env",           'fallback-model');
    mkdir "$tmpdir/.chatedit" or die;
    write_env_file("$tmpdir/.chatedit/priority-bot.env", 'priority-model');

    {
        no warnings 'once';
        $main::prog_name = 'priority-bot';
    }

    my $found = find_env_file();
    is($found, './.chatedit/priority-bot.env',
        'prog_name .chatedit/ takes priority over ./ai-chat.env fallback');

    chdir($orig_dir) or die;
    {
        no warnings 'once';
        $main::prog_name = 'ai-chat';
    }
}

# ============================================================================
# 7. find_config_file: 没有任何 env 文件时返回 undef
# ============================================================================
{
    my $tmpdir = tempdir(CLEANUP => 1);
    chdir($tmpdir) or die "Cannot chdir: $!";
    local $ENV{HOME} = $tmpdir;    # 隔离 ~/ 目录，避免真实 ~/.chatedit/ai-chat.env 被找到

    {
        no warnings 'once';
        $main::prog_name = 'no-env-bot';
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
# 8. load_env: 正确解析 env 文件并设置环境变量
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
# 9. load_env: --env 为空字符串时抑止查找，不加载任何 env 文件
# ============================================================================
{
    my $tmpdir = tempdir(CLEANUP => 1);
    chdir($tmpdir) or die "Cannot chdir: $!";
    write_env_file("$tmpdir/ai-chat.env", 'should-not-load');
    delete $ENV{API_MODEL};

    {
        no warnings 'once';
        $main::opt_env   = '';    # 空字符串 → 抑止
        $main::opt_url   = '';
        $main::opt_key   = '';
        $main::opt_model = '';
    }

    load_env();
    ok(!defined $ENV{API_MODEL}, 'load_env: --env "" suppresses file search');

    chdir($orig_dir) or die;
    reset_env_opts();
}

# ============================================================================
# 10. find_config_file('sys')：.sys 文件查找
# ============================================================================
{
    my $tmpdir = tempdir(CLEANUP => 1);
    chdir($tmpdir) or die "Cannot chdir: $!";

    open my $fh, '>', "$tmpdir/my-bot.sys" or die;
    print $fh "You are helpful.\n";
    close $fh;

    {
        no warnings 'once';
        $main::prog_name = 'my-bot';
    }

    my $found = find_system_file();
    is($found, './my-bot.sys', 'find_system_file: prog_name.sys found in CWD');

    chdir($orig_dir) or die;
    {
        no warnings 'once';
        $main::prog_name = 'ai-chat';
    }
}

# ============================================================================
# 11. find_config_file('json')：.json 模板文件查找
# ============================================================================
{
    my $tmpdir = tempdir(CLEANUP => 1);
    chdir($tmpdir) or die "Cannot chdir: $!";

    open my $fh, '>', "$tmpdir/ai-chat.json" or die;
    print $fh '{"model":"test","messages":[]}', "\n";
    close $fh;

    {
        no warnings 'once';
        $main::prog_name = 'other-tool';
        $main::opt_template = undef;
    }

    my $found = find_template_file();
    is($found, './ai-chat.json', 'find_template_file: ai-chat.json fallback found');

    chdir($orig_dir) or die;
    {
        no warnings 'once';
        $main::prog_name    = 'ai-chat';
        $main::opt_template = undef;
    }
}

# ============================================================================
# 12. 使用 testdata/ 中的实际测试文件验证（testdata 目录作为 CWD）
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
    }

    my $found = find_env_file();
    is($found, './test-prog.env', 'testdata/test-prog.env found when CWD=testdata');

    # test-chatedit 无 CWD 同名文件，但 .chatedit/test-chatedit.env 存在
    # 搜索顺序：prog_name 所有目录优先于 ai-chat 回退，故找到 .chatedit/test-chatedit.env
    {
        no warnings 'once';
        $main::prog_name = 'test-chatedit';
    }

    $found = find_env_file();
    is($found, './.chatedit/test-chatedit.env',
        'testdata: .chatedit/prog_name.env found before ai-chat.env fallback');

    chdir($orig_dir) or die;
    {
        no warnings 'once';
        $main::prog_name = 'ai-chat';
    }
}

done_testing();
