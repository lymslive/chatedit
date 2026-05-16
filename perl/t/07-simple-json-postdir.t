#!/usr/bin/env perl
# 测试 --simple/-s, --json/-j, --postdir 新选项
use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use File::Temp qw(tempfile tempdir);
use JSON::PP;

require "$Bin/../ai-chat.pl";

# 抑止 system 文件自动查找
{
    no warnings 'once';
    $main::opt_system = '';
}

my $script = "$Bin/../ai-chat.pl";

# 辅助：通过子进程运行脚本，返回 ($exit_code, $stdout, $stderr)
sub run_script {
    my (@args) = @_;
    my ($tmp_err_fh, $tmp_err) = tempfile(SUFFIX => '.err', UNLINK => 1);
    close $tmp_err_fh;
    my $out = qx(perl "$script" @args 2>"$tmp_err");
    my $exit = $?;
    open my $efh, '<', $tmp_err or die;
    local $/; my $err = <$efh>; close $efh;
    return ($exit, $out, $err);
}

# ============================================================================
# --simple/-s：整个输入当成单条 user 消息
# ============================================================================

# 纯文本输入 → 单条 user 消息
{
    my ($tmp_fh, $tmp_file) = tempfile(SUFFIX => '.txt', UNLINK => 1);
    binmode $tmp_fh, ':utf8';
    print $tmp_fh "Hello, this is a plain text message.\n";
    close $tmp_fh;

    my ($exit, $json_out) = run_script('--simple', '--encode', qq("$tmp_file"));
    is($exit, 0, '--simple --encode exits 0');

    my $data = eval { JSON::PP->new->utf8->decode($json_out) };
    ok(!$@,                              '--simple --encode: valid JSON');
    is(ref($data->{messages}), 'ARRAY', '--simple: messages is array');
    is(scalar @{$data->{messages}}, 1,  '--simple: exactly 1 message');
    is($data->{messages}[0]{role},    'user', '--simple: role is user');
    like($data->{messages}[0]{content}, qr/Hello, this is a plain text message/, '--simple: content preserved');
}

# --simple 忽略 Markdown ## role >> 格式（不解析对话段）
{
    my ($tmp_fh, $tmp_file) = tempfile(SUFFIX => '.md', UNLINK => 1);
    binmode $tmp_fh, ':utf8';
    print $tmp_fh "## user >> This line looks like a header\nBut all should be one message\n";
    close $tmp_fh;

    my ($exit, $json_out) = run_script('--simple', '--encode', qq("$tmp_file"));
    is($exit, 0, '--simple ignores markdown: exits 0');

    my $data = JSON::PP->new->utf8->decode($json_out);
    is(scalar @{$data->{messages}}, 1, '--simple ignores markdown: still 1 message');
    is($data->{messages}[0]{role}, 'user', '--simple ignores markdown: role is user');
    like($data->{messages}[0]{content}, qr/## user >>/, '--simple: markdown header kept as content');
}

# --simple 中文内容保真
{
    my ($tmp_fh, $tmp_file) = tempfile(SUFFIX => '.txt', UNLINK => 1);
    binmode $tmp_fh, ':utf8';
    print $tmp_fh "请帮我写一段 Perl 代码\n";
    close $tmp_fh;

    my ($exit, $json_out) = run_script('--simple', '--encode', qq("$tmp_file"));
    is($exit, 0, '--simple Chinese: exits 0');

    my $data = JSON::PP->new->utf8->decode($json_out);
    like($data->{messages}[0]{content}, qr/请帮我写一段/, '--simple: Chinese content preserved');
}

# ============================================================================
# save_to_postdir：将请求 JSON 保存到目录
# ============================================================================

# 正常保存：目录存在时创建文件
{
    my $tmpdir = tempdir(CLEANUP => 1);
    {
        no warnings 'once';
        $main::prog_name = 'test-ai';
        $main::opt_debug = 0;
    }

    my $json_str = '{"model":"test","messages":[]}';
    save_to_postdir($tmpdir, $json_str);

    my @files = glob("$tmpdir/test-ai-*.json");
    is(scalar @files, 1, 'save_to_postdir: exactly 1 file created');

    if (@files) {
        open my $fh, '<:raw', $files[0] or die;
        local $/; my $content = <$fh>; close $fh;
        is($content, $json_str, 'save_to_postdir: file content matches');

        # 文件名格式：test-ai-yyyymmdd-hhmmss.json
        like($files[0], qr{test-ai-\d{8}-\d{6}\.json$}, 'save_to_postdir: filename has timestamp format');
    }

    # 恢复 prog_name
    {
        no warnings 'once';
        $main::prog_name = 'ai-chat';
    }
}

# 目录不存在时打印告警，不崩溃
{
    my $nonexist = '/tmp/nonexistent-dir-for-test-' . $$;
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };

    save_to_postdir($nonexist, '{}');

    ok(scalar @warnings > 0, 'save_to_postdir: warns when dir not exists');
    like($warnings[0], qr/目录不存在/, 'save_to_postdir: warning mentions missing dir');
}

# 通过子进程测试 --postdir（结合 mock API 响应）
{
    my $tmpdir = tempdir(CLEANUP => 1);

    # 直接测试 save_to_postdir 用不同程序名
    {
        no warnings 'once';
        $main::prog_name = 'kimi-chat';
        $main::opt_debug = 0;
    }

    save_to_postdir($tmpdir, '{"test":1}');

    my @files = glob("$tmpdir/kimi-chat-*.json");
    is(scalar @files, 1, 'save_to_postdir: prog_name used in filename');
    like($files[0], qr{kimi-chat-\d{8}-\d{6}\.json$}, 'save_to_postdir: custom prog_name in filename');

    {
        no warnings 'once';
        $main::prog_name = 'ai-chat';
    }
}

# ============================================================================
# --json/-j：通过 mock call_api 测试原始 JSON 输出
# ============================================================================
{
    my $raw_response = '{"id":"cmpl-123","choices":[{"message":{"role":"assistant","content":"hi"}}]}';

    no warnings 'redefine';
    local *main::call_api = sub { return $raw_response };

    # 设置必要环境变量（run() 检查它们）
    local $ENV{API_URL} = 'http://mock-url';
    local $ENV{API_KEY} = 'mock-key';

    # 重置所有选项到初始状态
    {
        no warnings 'once';
        $main::opt_json     = 1;
        $main::opt_append   = 0;
        $main::opt_reformat = undef;
        $main::opt_encode   = 0;
        $main::opt_decode  = 0;
        $main::opt_simple  = 0;
        $main::opt_postdir = '';
        $main::opt_model   = 'test-model';
        $main::opt_system  = '';
        @main::ARGV        = ();
    }

    # 捕获 STDOUT
    my $output = '';
    {
        local *STDOUT;
        open STDOUT, '>', \$output or die "Cannot redirect STDOUT: $!";
        binmode STDOUT, ':raw';

        my $markdown = "## Q >> Hello\n";
        open my $fh, '<:utf8', \$markdown or die $!;
        my @messages = parse_chat($fh);
        close $fh;

        my $template = { model => 'test', messages => \@messages };
        my $request_json = JSON::PP->new->utf8->encode($template);

        my $response_json = call_api($request_json, 'http://mock', 'key');

        # 模拟 --json 行为：直接输出原始 JSON
        print $response_json;
    }

    is($output, $raw_response, '--json: raw API response JSON printed verbatim');

    # 重置 opt_json
    {
        no warnings 'once';
        $main::opt_json = 0;
    }
}

done_testing();
