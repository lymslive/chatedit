#!/usr/bin/env perl
# ai-chat.pl - 将 markdown 聊天文件转换为 AI API 的 JSON 请求体并可直接发送请求

use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use JSON::PP;
use File::Temp qw(tempfile);
use File::Basename qw(basename);

# 脚本名（去掉 .pl 后缀），用于配置文件自动查找（our 供测试文件覆盖）
our $prog_name = basename($0, '.pl');
our $VERSION   = '1.0';

# ---- 选项解析 ---------------------------------------------------------------

our $opt_template     = undef;
our $opt_debug        = 0;
our $opt_help         = 0;
our $opt_encode       = 0;
our $opt_decode       = 0;
our $opt_append       = 0;
our $opt_reformat     = undef;
our $opt_env          = undef;
our $opt_url          = '';
our $opt_key          = '';
our $opt_model        = '';
our $opt_system       = undef;  # undef=自动查找，''=抑止，其他=使用该值
our $opt_simple       = 0;
our $opt_json         = 0;
our $opt_postdir      = '';
our $opt_stream       = 0;
our $opt_version      = 0;

unless (caller) { run() }

sub run
{
    GetOptions(
        'template|t=s' => \$opt_template,
        'debug|d'      => \$opt_debug,
        'help|h'       => \$opt_help,
        'encode'       => \$opt_encode,
        'decode'       => \$opt_decode,
        'append|a'     => \$opt_append,
        'reformat=i'   => \$opt_reformat,
        'env=s'        => \$opt_env,
        'url=s'        => \$opt_url,
        'key=s'        => \$opt_key,
        'model=s'      => \$opt_model,
        'system:s'     => \$opt_system,
        'simple|s'     => \$opt_simple,
        'json|j'       => \$opt_json,
        'postdir=s'    => \$opt_postdir,
        'stream'       => \$opt_stream,
        'version|v'    => \$opt_version,
    ) or do { usage(); exit 1 };

    if ($opt_version) { print "$prog_name $VERSION\n"; exit 0 }
    if ($opt_help) { usage(); exit 0 }

    if ($opt_decode) {
        decode_to_md();
        exit 0;
    }

    load_env();

    $opt_append = 0 if $opt_encode;    # --encode 时 --append 无效

    my $input_file = @ARGV ? $ARGV[0] : undef;
    my $fh = open_input();

    my $template  = load_template();
    my @messages;
    if ($opt_simple) {
        local $/;
        my $content = <$fh>;
        close $fh;
        $content //= '';
        $content =~ s/\s+$//;
        @messages = ({ role => 'user', content => $content });
    }
    else {
        @messages = parse_chat($fh);
        close $fh;
    }

    inject_system(\@messages);

    my $model_val = $template->{model} // '';
    if ($model_val =~ /\$\{?API_MODEL\}?/) {
        $template->{model} = $ENV{API_MODEL} // $model_val;
    }

    my $is_stream = $opt_stream || (defined $template->{stream} && $template->{stream});
    $template->{stream} = JSON::PP::true if $is_stream;

    $template->{messages} = \@messages;

    if ($opt_encode) {
        my $json = JSON::PP->new->utf8->pretty->canonical(0);
        print $json->encode($template);
        exit 0;
    }

    my $api_url = $ENV{API_URL} // '';
    my $api_key = $ENV{API_KEY} // '';
    die "错误: 未设置 API URL，请通过 --url 参数或 env 文件中的 API_URL 配置\n" unless $api_url;
    die "错误: 未设置 API KEY，请通过 --key 参数或 env 文件中的 API_KEY 配置\n" unless $api_key;

    my $request_json = JSON::PP->new->utf8->canonical(0)->encode($template);
    warn "[debug] 请求 JSON: $request_json\n" if $opt_debug;

    my ($json_file, $is_temp) = prepare_request_file($request_json);

    if ($opt_debug) {
        my $masked = substr($api_key, 0, 6) . '****' . substr($api_key, -4);
        warn "[debug] curl: POST $api_url (key: $masked)\n";
    }

    if ($is_stream) {
        run_stream($json_file, $api_url, $api_key, $input_file);
    }
    else {
        run_non_stream($json_file, $api_url, $api_key, $input_file);
    }

    unlink $json_file if $is_temp && !$opt_debug;
}

# ============================================================================
# 两种运行模式：流式 / 非流式
# ============================================================================

sub run_non_stream
{
    my ($json_file, $api_url, $api_key, $input_file) = @_;

    my $response_json = call_api($json_file, $api_url, $api_key);

    if ($opt_json) {
        binmode STDOUT, ':raw';
        print $response_json;
        return;
    }

    my ($role, $content) = parse_response($response_json);

    if (!defined $content) {
        print STDERR $response_json, "\n";
        exit 1;
    }

    binmode STDOUT, ':utf8';

    if ($opt_append && !defined $input_file) {
        print_response(\*STDOUT, $role, $content, 1);
    }
    else {
        print_response(\*STDOUT, $role, $content, 0);

        if ($opt_append && defined $input_file) {
            my ($lines_appended, $reformed) = append_to_file($input_file, $role, $content);
            printf STDERR "# <!-- %d lines appended to file: %s; reformated lines: %d -->\n",
                $lines_appended, $input_file, $reformed;
        }
    }
}

sub run_stream
{
    my ($json_file, $api_url, $api_key, $input_file) = @_;

    if ($opt_json) {
        binmode STDOUT, ':raw';
        call_api_stream($json_file, $api_url, $api_key);
        return;
    }

    binmode STDOUT, ':utf8';
    local $| = 1;

    my $stdout_reformat;
    if ($opt_append && !defined $input_file) {
        $stdout_reformat = defined $opt_reformat ? $opt_reformat : 1;
    }
    else {
        $stdout_reformat = defined $opt_reformat ? $opt_reformat : 0;
    }

    # 角色标题延后到首个 delta 到达时（使用实际角色名）打印，避免硬编码 assistant
    my ($role, $content) = call_api_stream($json_file, $api_url, $api_key, $stdout_reformat);
    return unless defined $content;

    print "\n" unless $content =~ /\n$/;

    if ($opt_append && defined $input_file) {
        my ($lines_appended, $reformed) = append_to_file($input_file, $role, $content);
        printf STDERR "# <!-- %d lines appended to file: %s; reformated lines: %d -->\n",
            $lines_appended, $input_file, $reformed;
    }
}

# ============================================================================
# 子函数
# ============================================================================

# 读取整个文件内容，去除首尾空白，失败时 die
sub read_file_content
{
    my ($file) = @_;
    open my $fh, '<:utf8', $file
        or die "错误: 无法读取文件 '$file': $!\n";
    local $/;
    my $content = <$fh>;
    close $fh;
    $content //= '';
    $content =~ s/^\s+|\s+$//g;
    return $content;
}

# 按优先级自动搜索配置文件（prog_name 所有目录优先于 ai-chat 回退）
# 调用方负责在有命令行选项时跳过此函数
sub find_config_file
{
    my ($suffix) = @_;
    my @dirs  = ('.', './.chatedit');
    push @dirs, "$ENV{HOME}/.chatedit" if defined $ENV{HOME};
    my @names = ("$prog_name.$suffix");
    push @names, "ai-chat.$suffix" if $prog_name ne 'ai-chat';
    for my $name (@names) {
        for my $dir (@dirs) {
            my $f = "$dir/$name";
            if (-f $f) {
                warn "[debug] 找到配置文件: $f\n" if $opt_debug;
                return $f;
            }
        }
    }
    return undef;
}

sub find_env_file      { find_config_file('env') }
sub find_system_file   { find_config_file('sys') }
sub find_template_file { find_config_file('json') }

sub load_env
{
    my $env_file;
    if (defined $opt_env) {
        if (!$opt_env) {
            warn "[debug] --env 指定为空/0，抑止 env 文件查找\n" if $opt_debug;
        }
        elsif (!-f $opt_env) {
            warn "警告: --env 指定的文件不存在: $opt_env\n";
        }
        else {
            $env_file = $opt_env;
        }
    }
    else {
        $env_file = find_env_file();
    }

    if (defined $env_file) {
        warn "[debug] 加载 env 文件: $env_file\n" if $opt_debug;
        open my $fh, '<', $env_file
            or die "错误: 无法读取 env 文件 '$env_file': $!\n";
        while (<$fh>) {
            chomp;
            next if /^\s*#/ || /^\s*$/;
            if (/^\s*(\w+)\s*=\s*(.*?)\s*$/) {
                my ($k, $v) = ($1, $2);
                $v =~ s/^(['"])(.*)\1$/$2/;
                $ENV{$k} //= $v;
            }
        }
        close $fh;
    }
    $ENV{API_URL}   = $opt_url   if $opt_url;
    $ENV{API_KEY}   = $opt_key   if $opt_key;
    $ENV{API_MODEL} = $opt_model if $opt_model;
}

sub load_template
{
    my $file;
    if (defined $opt_template) {
        if (!$opt_template) {
            warn "[debug] --template 指定为空/0，抑止模板文件查找\n" if $opt_debug;
        }
        elsif (!-f $opt_template) {
            warn "警告: --template 指定的文件不存在: $opt_template\n";
        }
        else {
            $file = $opt_template;
        }
    }
    else {
        $file = find_template_file();
    }

    my $text;
    if (defined $file) {
        warn "[debug] 模板文件: $file\n" if $opt_debug;
        $text = read_file_content($file);
    }
    else {
        warn "[debug] 使用内联默认模板\n" if $opt_debug;
        $text = default_template();
    }

    my $data = eval { JSON::PP->new->utf8->decode($text) };
    if ($@) {
        die "错误: 模板 JSON 解析失败: $@\n";
    }
    return $data;
}

sub default_template
{
    return '{"model":"$API_MODEL","messages":[]}';
}

sub inject_system
{
    my ($messages) = @_;
    my $sys_content;

    if (defined $opt_system) {
        if ($opt_system && $opt_system ne '0') {
            $sys_content = $opt_system;
            if ($sys_content =~ /^@(.+)/) {
                my $file = $1;
                $file =~ s/^\s+|\s+$//g;
                $sys_content = read_file_content($file);
            }
        }
        # '' 或 '0' → 抑止，不插入
    }
    else {
        my $sys_file = find_system_file();
        if (defined $sys_file) {
            warn "[debug] 使用 system 文件: $sys_file\n" if $opt_debug;
            $sys_content = read_file_content($sys_file);
        }
    }

    if (defined $sys_content && $sys_content ne '') {
        if (!@$messages || $messages->[0]{role} ne 'system') {
            unshift @$messages, { role => 'system', content => $sys_content };
        }
    }
}

# 从 STDIN 读取到临时文件；若 --append 同时将输入复制到 stdout
sub open_stdin
{
    warn "[debug] 从 STDIN 读取输入（临时文件缓冲）\n" if $opt_debug;
    my ($tmp_fh, $tmp_file) = tempfile(DIR => '/tmp', SUFFIX => '.md', UNLINK => 1);
    binmode $tmp_fh, ':raw';

    my $last_chunk = '';
    if ($opt_append) {
        binmode STDOUT, ':raw';
        while (read(STDIN, my $chunk, 65536)) {
            print $tmp_fh $chunk;
            print STDOUT $chunk;
            $last_chunk = $chunk;
        }
        print STDOUT "\n" if length($last_chunk) && $last_chunk !~ /\n\s*$/;
    }
    else {
        while (read(STDIN, my $chunk, 65536)) {
            print $tmp_fh $chunk;
        }
    }
    close $tmp_fh;

    open my $fh, '<:utf8', $tmp_file
        or die "错误: 无法打开临时文件: $!\n";
    return $fh;
}

# 打开输入文件或调用 open_stdin，返回单个文件句柄
sub open_input
{
    if (@ARGV) {
        my $file = $ARGV[0];
        open my $fh, '<:utf8', $file
            or die "错误: 无法打开文件 '$file': $!\n";
        warn "[debug] 输入文件: $file\n" if $opt_debug;
        return $fh;
    }
    return open_stdin();
}

# 准备请求 JSON 文件：优先保存到 --postdir，失败时创建临时文件
# 返回 ($file_path, $is_temp)；$is_temp 为 1 时调用方负责 unlink
sub prepare_request_file
{
    my ($json_str) = @_;
    if ($opt_postdir ne '') {
        my $saved = save_to_postdir($opt_postdir, $json_str);
        return ($saved, 0) if $saved;
    }
    my ($tmp_fh, $tmp_file) = tempfile(DIR => '/tmp', SUFFIX => '.json', UNLINK => 0);
    binmode $tmp_fh, ':raw';
    print $tmp_fh $json_str;
    close $tmp_fh;
    warn "[debug] 请求临时文件: $tmp_file\n" if $opt_debug;
    return ($tmp_file, 1);
}

# 将请求 JSON 保存到 --postdir 目录，成功返回文件路径，失败返回 undef
sub save_to_postdir
{
    my ($dir, $json_str) = @_;
    unless (-d $dir) {
        warn "警告: --postdir 指定的目录不存在: $dir\n";
        return undef;
    }
    my @t    = localtime(time);
    my $ts   = sprintf('%04d%02d%02d-%02d%02d%02d',
                       $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);
    my $save = "$dir/${prog_name}-${ts}-$$.json";
    if (open my $pfh, '>:raw', $save) {
        print $pfh $json_str;
        close $pfh;
        warn "[debug] 已保存请求 JSON: $save\n" if $opt_debug;
        return $save;
    }
    else {
        warn "警告: 无法写入 postdir 文件 '$save': $!\n";
        return undef;
    }
}

# 调用 API，返回响应 JSON 字符串
sub call_api
{
    my ($json_file, $url, $key) = @_;

    my @cmd = (
        'curl', '-s', '-X', 'POST',
        '-H', 'Content-Type: application/json',
        '-H', "Authorization: Bearer $key",
        '-d', "\@$json_file",
        $url,
    );

    open my $resp_fh, '-|', @cmd
        or die "错误: 无法执行 curl: $!\n";
    local $/;
    my $response = <$resp_fh>;
    close $resp_fh;
    my $exit = $? >> 8;

    die "错误: curl 命令失败 (exit: $exit)\n" if $exit != 0;
    return $response // '';
}

# 流式调用 API（SSE）：实时输出到 stdout
# $print_header：若为真，在首个 delta 到达时打印 "## role >>" 标题行（使用实际角色名）
sub call_api_stream
{
    my ($json_file, $url, $key, $print_header) = @_;

    my @cmd = (
        'curl', '-s', '-X', 'POST',
        '-H', 'Content-Type: application/json',
        '-H', "Authorization: Bearer $key",
        '-d', "\@$json_file",
        $url,
    );

    open my $resp_fh, '-|', @cmd
        or die "错误: 无法执行 curl: $!\n";
    binmode $resp_fh, ':raw';

    my $content        = '';
    my $role           = 'assistant';   # 默认值；实际角色从首个 chunk 中提取
    my $header_printed = 0;

    while (defined(my $line = <$resp_fh>)) {
        $line =~ s/\r?\n$//;

        if ($opt_json) {
            print $line, "\n";
            next;
        }

        next unless $line =~ /^data:\s*(.+)$/;
        my $data = $1;
        next if $data eq '[DONE]';

        my $chunk = eval { JSON::PP->new->utf8->decode($data) };
        next if $@;

        my $delta_text = _extract_stream_delta($chunk, \$role);
        if ($delta_text ne '') {
            if ($print_header && !$header_printed) {
                print STDOUT "## $role >>\n\n";
                $header_printed = 1;
            }
            print STDOUT $delta_text;
            $content .= $delta_text;
        }
    }
    close $resp_fh;
    my $exit = $? >> 8;

    die "错误: curl 命令失败 (exit: $exit)\n" if $exit != 0;

    return $opt_json ? (undef, undef) : ($role, $content);
}

# 从 SSE chunk 中提取 delta 文本，同时更新 $role（通过引用）
sub _extract_stream_delta
{
    my ($chunk, $role_ref) = @_;

    if (ref($chunk->{choices}) eq 'ARRAY' && @{ $chunk->{choices} }) {
        my $delta = $chunk->{choices}[0]{delta} // {};
        $$role_ref = $delta->{role}
            if defined $delta->{role} && $delta->{role} ne '';
        return $delta->{content} // '';
    }

    if (($chunk->{type} // '') eq 'content_block_delta') {
        my $d = $chunk->{delta} // {};
        return $d->{text} // ''
            if ($d->{type} // '') eq 'text_delta';
        return '';
    }

    if (($chunk->{type} // '') eq 'message_start') {
        my $msg = $chunk->{message} // {};
        $$role_ref = $msg->{role} if defined $msg->{role};
    }

    return '';
}

# 解析 API 响应 JSON，返回 ($role, $content)；失败返回 (undef, undef)
sub parse_response
{
    my ($json_str) = @_;

    my $data = eval { JSON::PP->new->utf8->decode($json_str) };
    if ($@) {
        warn "错误: 无法解析 API 响应 JSON: $@\n";
        return (undef, undef);
    }

    if (exists $data->{choices}
        && ref($data->{choices}) eq 'ARRAY'
        && @{ $data->{choices} })
    {
        my $msg     = $data->{choices}[0]{message} // {};
        my $role    = $msg->{role}    // 'assistant';
        my $content = $msg->{content} // '';
        return ($role, $content);
    }

    if (exists $data->{content}
        && ref($data->{content}) eq 'ARRAY'
        && @{ $data->{content} })
    {
        my $role    = $data->{role} // 'assistant';
        my $content = join('', map { $_->{text} // '' } @{ $data->{content} });
        return ($role, $content);
    }

    return (undef, undef);
}

# 修正 AI 回复中的 Markdown 标题等级
# h1 → h3，h2 → h3，h3+ 各增加一级
sub fix_heading_level
{
    my ($content) = @_;

    my @lines = split /\n/, $content, -1;
    my $count = 0;
    for my $line (@lines) {
        next unless $line =~ /^(#+) /;
        $count++;
        my $level = length($1);
        if ($level == 1) {
            $line = '###' . substr($line, 1);  # # → ### (替换首个 #)
        }
        elsif ($level < 6) {
            $line = '#' . $line;               # h2→h3, ..., h5→h6
        }
        # $level >= 6: 已到 Markdown 最大标题级，保持不变
    }
    my $result = join("\n", @lines);
    return wantarray ? ($result, $count) : $result;
}

# 将响应打印到句柄
# $for_file: 1=按文件模式（默认 reformat=1），0=按 stdout 模式（默认 reformat=0）
sub print_response
{
    my ($fh, $role, $content, $for_file) = @_;
    $for_file //= 0;
    my $do_fmt = defined $opt_reformat ? $opt_reformat : ($for_file ? 1 : 0);
    $content = fix_heading_level($content) if $do_fmt;
    print $fh "## $role >>\n\n" if $do_fmt;
    print $fh $content, "\n";
}

# 追加响应到输入 .md 文件
# 返回 ($lines_appended, $reformed_count)
sub append_to_file
{
    my ($file, $role, $content) = @_;
    my $do_fmt = defined $opt_reformat ? $opt_reformat : 1;

    my $reformed_count = 0;
    if ($do_fmt) {
        ($content, $reformed_count) = fix_heading_level($content);
    }

    open my $wfh, '>>:utf8', $file
        or die "错误: 无法写入文件 '$file': $!\n";

    print $wfh "\n";

    my $lines_appended = 0;
    if ($do_fmt) {
        print $wfh "## $role >>\n\n";
        $lines_appended += 2;
    }

    my @content_lines = split /\n/, $content;
    $lines_appended += scalar(@content_lines);

    print $wfh $content, "\n";
    close $wfh;

    return ($lines_appended, $reformed_count);
}

# --decode: 读取文件或 STDIN 中的 JSON 请求体，输出 markdown 对话段
sub decode_to_md
{
    my $json_bytes;
    if (@ARGV) {
        open my $fh, '<:raw', $ARGV[0]
            or die "错误: 无法打开文件 '$ARGV[0]': $!\n";
        local $/;
        $json_bytes = <$fh>;
        close $fh;
    }
    else {
        local $/;
        $json_bytes = <STDIN>;
    }

    my $data = eval { JSON::PP->new->utf8->decode($json_bytes) };
    die "错误: 无法解析 JSON: $@\n" if $@;

    binmode STDOUT, ':utf8';
    for my $msg (@{ $data->{messages} // [] }) {
        my $role    = $msg->{role}    // 'unknown';
        my $content = $msg->{content} // '';
        print "## $role >>\n\n$content\n\n";
    }
}

# 解析 markdown 聊天文件，返回 message 列表
sub parse_chat
{
    my ($fh) = @_;
    my @messages;

    my $cur_role  = '';
    my @cur_lines = ();
    my $in_code   = 0;

    my $flush = sub {
        return unless $cur_role;
        my $content = join("\n", @cur_lines);
        $content =~ s/^\n+//;
        $content =~ s/\n+$//;
        push @messages, { role => $cur_role, content => $content };
        $cur_role  = '';
        @cur_lines = ();
    };

    while (defined(my $line = <$fh>)) {
        chomp $line;

        if ($line =~ /^```/) {
            $in_code = !$in_code;
            push @cur_lines, $line if $cur_role;
            next;
        }

        if ($in_code) {
            push @cur_lines, $line if $cur_role;
            next;
        }

        if ($line =~ /^##\s+(system|user|assistant|[PQA])\s*>>(.*)/i) {
            my ($raw_role, $rest) = ($1, $2);
            $flush->();
            $cur_role  = normalize_role($raw_role);
            @cur_lines = ();
            $rest =~ s/^\s+//;
            push @cur_lines, $rest if $rest ne '';
            next;
        }

        if ($line =~ /^##[^#]/ || $line eq '##') {
            $flush->();
            next;
        }

        if ($line =~ /^#[^#]/ || $line eq '#') {
            $flush->();
            next;
        }

        if ($cur_role) {
            if ($line =~ /^@\s*(\S.*)$/) {
                my $path = $1;
                $path =~ s/\s+$//;
                my ($ok, @included) = include_file($path);
                if (!$ok) {
                    push @cur_lines, "$line (Read Error)";
                }
                elsif (!grep { /\S/ } @included) {
                    push @cur_lines, "$line (Read Empty)";
                }
                else {
                    push @cur_lines, @included;
                }
                next;
            }

            if ($line =~ /^!\s*(\S.*)$/) {
                my $cmd = $1;
                $cmd =~ s/\s+$//;
                my ($ok, @output) = run_command($cmd);
                if (!$ok) {
                    push @cur_lines, "$line (Read Error)";
                }
                elsif (!grep { /\S/ } @output) {
                    push @cur_lines, "$line (Read Empty)";
                }
                else {
                    push @cur_lines, @output;
                }
                next;
            }

            push @cur_lines, $line;
        }
    }

    $flush->();
    return @messages;
}

sub normalize_role
{
    my ($role) = @_;
    my %abbr = ( P => 'system', Q => 'user', A => 'assistant' );
    return $abbr{ uc($role) } // lc($role);
}

sub include_file
{
    my ($path) = @_;
    unless (-f $path) {
        warn "警告: 引用文件不存在: $path\n";
        return (0);
    }
    open my $fh, '<:utf8', $path
        or do { warn "警告: 无法读取文件 '$path': $!\n"; return (0) };
    my @lines = map { chomp; $_ } <$fh>;
    close $fh;
    return (1, @lines);
}

sub run_command
{
    my ($cmd) = @_;
    warn "[debug] 执行命令: $cmd\n" if $opt_debug;
    my $output = qx($cmd);
    if ($? != 0) {
        warn "警告: 命令退出码非零 ($?): $cmd\n";
        return (0);
    }
    chomp $output;
    return (1, split /\n/, $output);
}

sub usage
{
    print STDERR <<'USAGE';
用法: ai-chat.pl [选项] [input.md]
      ai-chat.pl [选项] < input.md

将 markdown 聊天文件解析为 AI API JSON 并直接发送请求，回复打印至 stdout；
可同时通过 --append/-a 将回复追加到输入文件（或与 stdin 联用时将完整对话输出到 stdout）。

选项（API 连接）:
  --env <file>       指定 env 文件（默认按优先级搜索 ai-chat.env）
  --url <url>        API URL（覆盖 env 文件 API_URL）
  --key <key>        API Key（覆盖 env 文件 API_KEY）
  --model <model>    模型名（覆盖 env 文件 API_MODEL）
  --system [msg]     system 消息；以 @ 开头时读取文件；空参数或不带参数时抑止自动查找
  -t, --template <file>  指定 JSON 模板文件（默认按优先级搜索）

选项（行为）:
  -a, --append       将 AI 回复追加到输入 .md 文件；STDIN 模式则先将原输入复制到 stdout
                     再接着追加回复（stdout 充当"虚拟文件"）
  --reformat 0|1    控制是否格式化输出（添加 ## role >> 标题行 + 修正标题等级）；
                     追加到文件时默认 1（开启），打印 stdout 时默认 0（关闭）
  -s, --simple       将整个输入当成简单 user 消息，跳过 Markdown 解析
  --stream           启用流式响应（SSE）；实时打印到 stdout；若同时指定 -a 则完成后也追加到文件

选项（调试）:
  --encode           只输出组装的 JSON（pretty），不发送请求（与 ai-curl.sh 管道兼容）
  --decode           逆向：输入 API JSON，输出 markdown 对话段
  -j, --json         直接输出原始 API 响应 JSON，忽略 -a
  --postdir <dir>    将发送的请求 JSON 保存到指定目录（命名格式：程序名-yyyymmdd-hhmmss-PID.json）
  -d, --debug            打印调试信息到 stderr
  -v, --version          显示版本号
  -h, --help             显示此帮助

用法示例:
  # 发送请求并打印响应到 stdout
  perl/ai-chat.pl chat.md

  # 打印响应同时追加到文件；并在 stderr 打印摘要
  perl/ai-chat.pl -a chat.md

  # STDIN 模式：将对话完整输出到 stdout（原文 + AI 回复）
  cat chat.md | perl/ai-chat.pl -a

  # 流式输出 + 追加文件
  perl/ai-chat.pl --stream -a chat.md

  # 仅编码兼容管道其他 API 请求工具
  cat chat.md | perl/ai-chat.pl --encode | bash/ai-curl.sh

  # 编解码互逆测试
  cat chat.md | perl/ai-chat.pl --encode | perl/ai-chat.pl --decode

  # 抑止 system 自动查找
  perl/ai-chat.pl --system "" -a chat.md

env 文件搜索顺序（PROG 为脚本名去掉 .pl 后缀，如软链接 kimi-chat 则为 kimi-chat）:
  1. --env 指定的文件
  2. ./$PROG.env  （再回退 ./ai-chat.env）
  3. ./.chatedit/$PROG.env  （再回退 ./.chatedit/ai-chat.env）
  4. ~/.chatedit/$PROG.env  （再回退 ~/.chatedit/ai-chat.env）

system 文件自动搜索顺序（未指定 --system 时）:
  1. ./$PROG.sys  （再回退 ./ai-chat.sys）
  2. ./.chatedit/$PROG.sys  （再回退 ./.chatedit/ai-chat.sys）
  3. ~/.chatedit/$PROG.sys  （再回退 ~/.chatedit/ai-chat.sys）

模板文件搜索顺序:
  1. --template 指定的文件
  2. ./$PROG.json  （再回退 ./ai-chat.json）
  3. ./.chatedit/$PROG.json  （再回退 ./.chatedit/ai-chat.json）
  4. ~/.chatedit/$PROG.json  （再回退 ~/.chatedit/ai-chat.json）
  5. 内联固定模板（仅含 model 和空 messages）
USAGE
}

__END__

=head1 NAME

ai-chat.pl - 将 markdown 聊天文件转换为 AI API 的 JSON 请求体并可直接发送请求

=head1 SYNOPSIS

    # 发送请求，响应打印到 stdout
    ai-chat.pl chat.md

    # 发送请求，响应同时追加到文件（多轮对话）
    ai-chat.pl -a chat.md

    # STDIN 模式：原文 + AI 回复一起输出到 stdout
    cat chat.md | ai-chat.pl -a

    # 只组装 JSON，不发请求（但可管道至其他请求工具）
    cat chat.md | ai-chat.pl --encode | bash/ai-curl.sh

    # 编解码互逆测试
    cat chat.md | ai-chat.pl --encode | ai-chat.pl --decode

=head1 DESCRIPTION

解析遵循 docs/chat-format.md 规范的 markdown 聊天文件，提取对话内容，
合并到 JSON 模板的 messages 数组中，通过 curl 调用 API。

输出分两阶段：
1. 阶段一：始终将 AI 回复打印到 stdout（默认无格式化标题行）
2. 阶段二：若指定 C<-a>，将回复追加到输入文件（默认开启格式化），
   并向 stderr 打印追加摘要行。

当从 stdin 读取且指定 C<-a> 时，stdout 充当"虚拟文件"：先复制原输入，
再接续输出带格式的 AI 回复（两阶段合并）。

=head1 OPTIONS

=over 4

=item B<--env> I<file>

指定 env 文件路径，按优先级搜索 ai-chat.env。

=item B<--url>, B<--key>, B<--model>

直接指定 API URL/Key/模型，优先级高于 env 文件。

=item B<--system> [I<msg>]

system 消息内容；以 C<@file> 形式读取文件；不带参数或空参数时
抑止自动查找 ai-chat.sys。

=item B<-a>, B<--append>

将 AI 回复追加到输入 .md 文件末尾。
若从 stdin 读取，则先将原输入复制到 stdout，再接续追加带格式的响应。
追加完成后向 stderr 输出追加摘要（仅有实际文件时）。

=item B<--reformat> I<0|1>

控制是否对输出进行格式化（添加 C<## role E<gt>E<gt>> 标题行 +
修正 AI 回复中的 Markdown 标题等级，防止 h1/h2 干扰多轮对话解析）。
追加到文件时默认 C<1>（开启），打印到 stdout 时默认 C<0>（关闭）。
显式指定时对所有输出路径生效。

=item B<-s>, B<--simple>

将整个输入内容当成一段 user 消息，不解析 Markdown 格式。

=item B<-j>, B<--json>

直接将 API 原始响应 JSON 输出到标准输出，忽略 C<-a> 选项。
与 C<--stream> 合用时输出原始 SSE 行流。

=item B<--stream>

启用流式响应（SSE）。将 C<"stream": true> 写入请求 JSON，并逐 delta 实时打印到标准输出。
若 JSON 模板中已包含 C<"stream": true>，无需额外指定此选项。
与 C<-a> 合用时，流式输出结束后将完整响应追加到输入文件。
与 C<-j> 合用时，直接转发原始 SSE 行到标准输出。

=item B<--postdir> I<dir>

将发送给 API 的请求 JSON 保存到指定目录，
文件名格式为 C<程序名-yyyymmdd-hhmmss-PID.json>。
目录不存在时打印告警，不自动创建目录。

=item B<--encode>

只输出组装的 JSON（pretty 格式），不发送 API 请求。
相当于原始 ai-chat.pl 的行为，可与 ai-curl.sh 管道联用。

=item B<--decode>

逆向操作：读取 API 请求 JSON，输出 markdown 对话段系列。

=item B<-t>, B<--template> I<file>

指定 JSON 模板文件。

=item B<-d>, B<--debug>

将调试信息输出到标准错误。

=item B<-h>, B<--help>

显示帮助信息。

=back

=head1 AUTHOR

lymslive

=cut
