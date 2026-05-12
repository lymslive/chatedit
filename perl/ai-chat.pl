#!/usr/bin/env perl
# ai-chat.pl - 将 markdown 聊天文件转换为 AI API 的 JSON 请求体并可直接发送请求

use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use JSON::PP;
use File::Temp qw(tempfile);

# ---- 选项解析 ---------------------------------------------------------------

my $opt_template     = '';
my $opt_debug        = 0;
my $opt_help         = 0;
my $opt_encode       = 0;   # 只输出 JSON（pretty），不发请求（原 ai-chat.pl 行为）
my $opt_decode       = 0;   # 输入 JSON，输出 markdown
my $opt_inplace      = 0;   # 原位修改输入 .md 文件（-i / --inplace）
my $opt_header       = 0;   # 打印 ## role >> 标题
my $opt_env          = '';
my $opt_url          = '';
my $opt_key          = '';
my $opt_model        = '';
my $opt_system_given = 0;   # --system 是否被指定
my $opt_system       = '';  # --system 的值（空串表示抑止自动查找）

GetOptions(
    'template|t=s' => \$opt_template,
    'debug|d'      => \$opt_debug,
    'help|h'       => \$opt_help,
    'encode'       => \$opt_encode,
    'decode'       => \$opt_decode,
    'inplace|i'    => \$opt_inplace,
    'header'       => \$opt_header,
    'env=s'        => \$opt_env,
    'url=s'        => \$opt_url,
    'key=s'        => \$opt_key,
    'model=s'      => \$opt_model,
    'system:s'     => sub { $opt_system_given = 1; $opt_system = defined $_[1] ? $_[1] : '' },
) or do { usage(); exit 1 };

if ($opt_help) { usage(); exit 0 }

# -i 隐含 --header
$opt_header = 1 if $opt_inplace;

# ---- 加载环境变量 -----------------------------------------------------------

load_env();

# ---- 主流程 -----------------------------------------------------------------

if ($opt_decode) {
    my $fh = open_file_or_stdin();
    decode_to_md($fh);
    close $fh;
    exit 0;
}

my $input_file = @ARGV ? $ARGV[0] : undef;
my ($fh, $stdin_buffer) = open_input();

my $template  = load_template();
my @messages  = parse_chat($fh);
close $fh;

# 注入 system 消息
inject_system(\@messages);

# 替换模板 model 字段中的 $API_MODEL 占位符
my $model_val = $template->{model} // '';
if ($model_val =~ /\$\{?API_MODEL\}?/) {
    $template->{model} = $ENV{API_MODEL} // $model_val;
}

$template->{messages} = \@messages;

if ($opt_encode) {
    # 只打印 JSON（pretty 格式，便于调试），兼容原有管道用法
    my $json = JSON::PP->new->utf8->pretty->canonical(0);
    print $json->encode($template);
    exit 0;
}

# ---- 调用 API ---------------------------------------------------------------

my $api_url = $ENV{API_URL} // '';
my $api_key = $ENV{API_KEY} // '';
die "错误: 未设置 API URL，请通过 --url 参数或 env 文件中的 API_URL 配置\n" unless $api_url;
die "错误: 未设置 API KEY，请通过 --key 参数或 env 文件中的 API_KEY 配置\n" unless $api_key;

my $request_json = JSON::PP->new->utf8->canonical(0)->encode($template);
warn "[debug] 请求 JSON: $request_json\n" if $opt_debug;

my $response_json = call_api($request_json, $api_url, $api_key);
my ($role, $content) = parse_response($response_json);

if (!defined $content) {
    print STDERR $response_json, "\n";
    exit 1;
}

# ---- 输出响应 ---------------------------------------------------------------

if ($opt_inplace && defined $input_file) {
    # 有输入文件：原位追加
    append_to_file($input_file, $role, $content);
} elsif ($opt_inplace) {
    # STDIN 模式：先复制原输入到 STDOUT（原始字节），再追加响应（utf8）
    if (defined $stdin_buffer && length($stdin_buffer)) {
        binmode STDOUT, ':raw';
        print $stdin_buffer;
        binmode STDOUT, ':utf8';
        # 末尾非空行时补一空行
        print "\n" if $stdin_buffer !~ /\n\s*$/;
    } else {
        binmode STDOUT, ':utf8';
    }
    print_response(\*STDOUT, $role, $content);
} else {
    binmode STDOUT, ':utf8';
    print_response(\*STDOUT, $role, $content);
}

# ============================================================================
# 子函数
# ============================================================================

# 加载 env 文件并设置环境变量，命令行选项覆盖 env 文件
sub load_env {
    my $env_file = find_env_file();
    if (defined $env_file) {
        warn "[debug] 加载 env 文件: $env_file\n" if $opt_debug;
        open my $fh, '<', $env_file
            or die "错误: 无法读取 env 文件 '$env_file': $!\n";
        while (<$fh>) {
            chomp;
            next if /^\s*#/ || /^\s*$/;
            if (/^\s*(\w+)\s*=\s*(.*?)\s*$/) {
                my ($k, $v) = ($1, $2);
                $v =~ s/^(['"])(.*)\1$/$2/;    # 去掉首尾引号
                $ENV{$k} //= $v;               # env 文件不覆盖已有环境变量
            }
        }
        close $fh;
    }
    # 命令行选项优先级最高
    $ENV{API_URL}   = $opt_url   if $opt_url;
    $ENV{API_KEY}   = $opt_key   if $opt_key;
    $ENV{API_MODEL} = $opt_model if $opt_model;
}

# 按优先级查找 env 文件
sub find_env_file {
    my @candidates = (
        $opt_env,
        './ai-curl.env',
        './.chatedit/ai-curl.env',
        "$ENV{HOME}/.chatedit/ai-curl.env",
    );
    for my $f (@candidates) {
        next unless defined $f && $f ne '';
        return $f if -f $f;
    }
    return undef;
}

# 打开输入：文件时返回 ($fh, undef)，STDIN 时写入临时文件后返回 ($fh, $raw_bytes)
sub open_input {
    if (@ARGV) {
        my $file = $ARGV[0];
        open my $fh, '<:utf8', $file
            or die "错误: 无法打开文件 '$file': $!\n";
        warn "[debug] 输入文件: $file\n" if $opt_debug;
        return ($fh, undef);
    }
    else {
        warn "[debug] 从 STDIN 读取输入（临时文件缓冲）\n" if $opt_debug;
        # 将 STDIN 写入临时文件，避免宽字符 in-memory filehandle 的 utf8 层限制
        my ($tmp_fh, $tmp_file) = tempfile(DIR => '/tmp', SUFFIX => '.md', UNLINK => 1);
        binmode $tmp_fh, ':raw';
        while (read(STDIN, my $chunk, 65536)) { print $tmp_fh $chunk }
        close $tmp_fh;

        # 读取原始字节用于后续 stdout 复制输出
        open my $buf_fh, '<:raw', $tmp_file
            or die "错误: 无法读取临时文件: $!\n";
        local $/;
        my $buffer = <$buf_fh>;
        close $buf_fh;

        # 以 utf8 解码方式重新打开，供 parse_chat 使用
        open my $fh, '<:utf8', $tmp_file
            or die "错误: 无法打开临时文件: $!\n";
        return ($fh, $buffer);
    }
}

# 打开文件或 STDIN（用于 --decode 等无需缓冲的场景，以原始字节读取供 JSON::PP->utf8->decode）
sub open_file_or_stdin {
    if (@ARGV) {
        my $file = $ARGV[0];
        open my $fh, '<:raw', $file
            or die "错误: 无法打开文件 '$file': $!\n";
        return $fh;
    }
    else {
        # 保持 STDIN 原始字节，供 JSON::PP->utf8->decode 使用
        return \*STDIN;
    }
}

# 注入 system 消息到 messages 首部
sub inject_system {
    my ($messages) = @_;
    my $sys_content;

    if ($opt_system_given) {
        # --system 选项已给出
        if ($opt_system ne '') {
            $sys_content = $opt_system;
            # 以 @ 开头时读取文件
            if ($sys_content =~ /^@(.+)/) {
                my $file = $1;
                $file =~ s/^\s+|\s+$//g;
                open my $fh, '<:utf8', $file
                    or die "错误: system 文件不存在: $file\n";
                local $/;
                $sys_content = <$fh>;
                close $fh;
                chomp $sys_content;
            }
        }
        # 空字符串 → 抑止，不插入
    }
    else {
        # 未指定 --system：自动查找 ai-chat.sys
        my $sys_file = find_system_file();
        if (defined $sys_file) {
            open my $fh, '<:utf8', $sys_file
                or die "错误: 无法读取 system 文件 '$sys_file': $!\n";
            local $/;
            $sys_content = <$fh>;
            close $fh;
            chomp $sys_content;
            warn "[debug] 使用 system 文件: $sys_file\n" if $opt_debug;
        }
    }

    if (defined $sys_content && $sys_content ne '') {
        # 仅当 messages 首条不是 system 时才插入
        if (!@$messages || $messages->[0]{role} ne 'system') {
            unshift @$messages, { role => 'system', content => $sys_content };
        }
    }
}

# 按优先级查找 ai-chat.sys 文件
sub find_system_file {
    my @candidates = (
        './ai-chat.sys',
        './.chatedit/ai-chat.sys',
        "$ENV{HOME}/.chatedit/ai-chat.sys",
    );
    for my $f (@candidates) {
        return $f if -f $f;
    }
    return undef;
}

# 调用 API，返回响应 JSON 字符串
sub call_api {
    my ($json, $url, $key) = @_;

    # 写入临时文件（避免命令行长度限制，也更安全）
    my ($tmp_fh, $tmp_file) = tempfile(DIR => '/tmp', SUFFIX => '.json', UNLINK => 0);
    binmode $tmp_fh, ':utf8';
    print $tmp_fh $json;
    close $tmp_fh;

    warn "[debug] 请求临时文件: $tmp_file\n" if $opt_debug;
    if ($opt_debug) {
        my $masked = substr($key, 0, 6) . '****' . substr($key, -4);
        warn "[debug] curl: POST $url (key: $masked)\n";
    }

    # 使用列表形式 open，不经过 shell，避免注入风险
    my @cmd = (
        'curl', '-s', '-X', 'POST',
        '-H', 'Content-Type: application/json',
        '-H', "Authorization: Bearer $key",
        '-d', "\@$tmp_file",
        $url,
    );

    open my $resp_fh, '-|', @cmd
        or die "错误: 无法执行 curl: $!\n";
    # 保持原始字节，供 JSON::PP->utf8->decode 使用
    local $/;
    my $response = <$resp_fh>;
    close $resp_fh;
    my $exit = $? >> 8;

    unlink $tmp_file unless $opt_debug;

    die "错误: curl 命令失败 (exit: $exit)\n" if $exit != 0;
    return $response // '';
}

# 解析 API 响应 JSON，返回 ($role, $content)；失败返回 (undef, undef)
sub parse_response {
    my ($json_str) = @_;

    my $data = eval { JSON::PP->new->utf8->decode($json_str) };
    if ($@) {
        warn "错误: 无法解析 API 响应 JSON: $@\n";
        return (undef, undef);
    }

    # OpenAI 兼容格式: .choices[].message.content
    if (exists $data->{choices}
        && ref($data->{choices}) eq 'ARRAY'
        && @{ $data->{choices} })
    {
        my $msg     = $data->{choices}[0]{message} // {};
        my $role    = $msg->{role}    // 'assistant';
        my $content = $msg->{content} // '';
        return ($role, $content);
    }

    # Anthropic 原生格式: .content[].text
    if (exists $data->{content}
        && ref($data->{content}) eq 'ARRAY'
        && @{ $data->{content} })
    {
        my $role    = $data->{role} // 'assistant';
        my $content = join('', map { $_->{text} // '' } @{ $data->{content} });
        return ($role, $content);
    }

    # 其他情况（含 error 字段）视为错误
    return (undef, undef);
}

# 将响应打印到句柄（可带 ## role >> 标题）
sub print_response {
    my ($fh, $role, $content) = @_;
    if ($opt_header) {
        print $fh "## $role >>\n\n";
    }
    print $fh $content, "\n";
}

# 原位追加响应到输入 .md 文件
sub append_to_file {
    my ($file, $role, $content) = @_;

    # 检查文件最后一行是否为空行
    open my $rfh, '<:utf8', $file
        or die "错误: 无法读取文件 '$file': $!\n";
    my $last_line = '';
    while (<$rfh>) { $last_line = $_ }
    close $rfh;

    open my $wfh, '>>:utf8', $file
        or die "错误: 无法写入文件 '$file': $!\n";

    # 末尾非空行时补一空行作分隔
    print $wfh "\n" if $last_line !~ /^\s*$/;

    print $wfh "## $role >>\n\n";
    print $wfh $content, "\n";
    close $wfh;
}

# --decode: 输入 JSON 请求体（原始字节），输出 markdown 对话段
sub decode_to_md {
    my ($fh) = @_;
    local $/;
    my $json_bytes = <$fh>;

    my $data = eval { JSON::PP->new->utf8->decode($json_bytes) };
    die "错误: 无法解析 JSON: $@\n" if $@;

    binmode STDOUT, ':utf8';
    my $messages = $data->{messages} // [];
    for my $msg (@$messages) {
        my $role    = $msg->{role}    // 'unknown';
        my $content = $msg->{content} // '';
        print "## $role >>\n\n";
        print $content, "\n\n";
    }
}

# ---- 原有子函数 -------------------------------------------------------------

# 查找并加载 JSON 模板，返回 hashref
sub load_template {
    my $file = find_template_file();
    my $text;
    if (defined $file) {
        warn "[debug] 模板文件: $file\n" if $opt_debug;
        open my $fh, '<:utf8', $file
            or die "错误: 无法读取模板文件 '$file': $!\n";
        local $/;
        $text = <$fh>;
        close $fh;
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

# 按优先级查找模板文件，找不到返回 undef
sub find_template_file {
    my @candidates = (
        $opt_template,
        './ai-chat.json',
        './.chatedit/ai-chat.json',
        "$ENV{HOME}/.chatedit/ai-chat.json",
    );
    for my $f (@candidates) {
        next unless defined $f && $f ne '';
        return $f if -f $f;
    }
    return undef;
}

# 内联固定模板（无外部模板文件时使用）
sub default_template {
    return '{"model":"$API_MODEL","messages":[]}';
}

# 解析 markdown 聊天文件，返回 message 列表（每个元素为 {role, content} hashref）
sub parse_chat {
    my ($fh) = @_;
    my @messages;

    my $cur_role  = '';      # 当前对话段的 role，空表示不在对话段内
    my @cur_lines = ();      # 当前对话段积累的内容行
    my $in_code   = 0;       # 是否在三反引号代码块中

    my $flush = sub {
        return unless $cur_role;
        my $content = join("\n", @cur_lines);
        $content =~ s/\n+$//;    # 去掉尾部空行
        push @messages, { role => $cur_role, content => $content };
        $cur_role  = '';
        @cur_lines = ();
    };

    while (defined(my $line = <$fh>)) {
        chomp $line;

        # 跟踪代码块（三反引号），块内不处理特殊标记
        if ($line =~ /^```/) {
            $in_code = !$in_code;
            push @cur_lines, $line if $cur_role;
            next;
        }

        if ($in_code) {
            push @cur_lines, $line if $cur_role;
            next;
        }

        # 尝试匹配 ## role >> 对话段开头
        if ($line =~ /^##\s+(system|user|assistant|[PQA])\s*>>(.*)/i) {
            my ($raw_role, $rest) = ($1, $2);
            $flush->();
            $cur_role  = normalize_role($raw_role);
            @cur_lines = ();
            $rest =~ s/^\s+//;    # 去掉 >> 后的前导空格
            push @cur_lines, $rest if $rest ne '';
            next;
        }

        # ## 开头但不是对话段标题 → 忽略/分隔，结束当前段
        # 注意：只匹配恰好两个 # 开头（即 ^## 后不再跟 #），### 等子标题在对话段内为普通内容行
        if ($line =~ /^##[^#]/ || $line eq '##') {
            $flush->();
            next;
        }

        # # 开头（且不是 ## 开头）→ 注释行，结束当前对话段
        if ($line =~ /^#[^#]/ || $line eq '#') {
            $flush->();
            next;
        }

        # 当前在对话段内
        if ($cur_role) {
            # @file 引入文件内容
            if ($line =~ /^@\s*(\S.*)$/) {
                my $path = $1;
                $path =~ s/\s+$//;
                my ($ok, @included) = read_file_lines($path);
                if (!$ok) {
                    push @cur_lines, "$line (Read Error)";
                } elsif (!grep { /\S/ } @included) {
                    push @cur_lines, "$line (Read Empty)";
                } else {
                    push @cur_lines, @included;
                }
                next;
            }

            # !cmd 捕获命令输出
            if ($line =~ /^!\s*(\S.*)$/) {
                my $cmd = $1;
                $cmd =~ s/\s+$//;
                my ($ok, @output) = run_command($cmd);
                if (!$ok) {
                    push @cur_lines, "$line (Read Error)";
                } elsif (!grep { /\S/ } @output) {
                    push @cur_lines, "$line (Read Empty)";
                } else {
                    push @cur_lines, @output;
                }
                next;
            }

            # 普通内容行（包括 ### 及以上子标题，保留为内容）
            push @cur_lines, $line;
        }
    }

    $flush->();
    return @messages;
}

# 角色名归一化：P→system, Q→user, A→assistant，其余转小写
sub normalize_role {
    my ($role) = @_;
    my %abbr = ( P => 'system', Q => 'user', A => 'assistant' );
    return $abbr{ uc($role) } // lc($role);
}

# 读取文件内容为行数组，返回 ($ok, @lines)；$ok 为 0 表示读取失败
sub read_file_lines {
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

# 执行 shell 命令，返回 ($ok, @lines)；$ok 为 0 表示命令失败
sub run_command {
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

# 打印用法说明
sub usage {
    print STDERR <<'USAGE';
用法: ai-chat.pl [选项] [input.md]
      ai-chat.pl [选项] < input.md

将 markdown 聊天文件解析为 AI API JSON 并直接发送请求，回复写回文件或打印至标准输出。

选项（API 连接）:
  --env <file>       指定 env 文件（默认按优先级搜索 ai-curl.env）
  --url <url>        API URL（覆盖 env 文件 API_URL）
  --key <key>        API Key（覆盖 env 文件 API_KEY）
  --model <model>    模型名（覆盖 env 文件 API_MODEL）
  --system [msg]     system 消息；以 @ 开头时读取文件；空参数或不带参数时抑止自动查找

选项（行为）:
  -i, --inplace      原位修改输入 .md 文件（隐含 --header）；STDIN 模式则复制输入到 STDOUT
  --header           在响应前打印 ## role >> 标题行
  --encode           只输出组装的 JSON（pretty），不发送请求（与 ai-curl.sh 管道兼容）
  --decode           逆向：输入 API JSON，输出 markdown 对话段

选项（调试）:
  -t, --template <file>  指定 JSON 模板文件（默认按优先级搜索）
  -d, --debug            打印调试信息到 stderr
  -h, --help             显示此帮助

用法示例:
  # 直接发送请求，回复写回文件（多轮对话）
  perl/ai-chat.pl -i chat.md

  # 打印响应到标准输出（带标题）
  perl/ai-chat.pl --header chat.md

  # 兼容旧管道用法
  cat chat.md | perl/ai-chat.pl --encode | bash/ai-curl.sh

  # 编解码互逆测试
  cat chat.md | perl/ai-chat.pl --encode | perl/ai-chat.pl --decode

  # 抑止 system 自动查找
  perl/ai-chat.pl --system "" -i chat.md

env 文件搜索顺序:
  1. --env 指定的文件
  2. ./ai-curl.env
  3. ./.chatedit/ai-curl.env
  4. ~/.chatedit/ai-curl.env

system 文件自动搜索顺序（未指定 --system 时）:
  1. ./ai-chat.sys
  2. ./.chatedit/ai-chat.sys
  3. ~/.chatedit/ai-chat.sys

模板文件搜索顺序:
  1. --template 指定的文件
  2. ./ai-chat.json
  3. ./.chatedit/ai-chat.json
  4. ~/.chatedit/ai-chat.json
  5. 内联固定模板（仅含 model 和空 messages）
USAGE
}

__END__

=head1 NAME

ai-chat.pl - 将 markdown 聊天文件转换为 AI API 的 JSON 请求体并可直接发送请求

=head1 SYNOPSIS

    # 直接发送请求，回复追加到文件（多轮对话）
    ai-chat.pl -i chat.md

    # 发送请求，响应打印到 STDOUT
    ai-chat.pl chat.md
    ai-chat.pl --header chat.md

    # 只组装 JSON，不发请求（兼容原有管道用法）
    cat chat.md | ai-chat.pl --encode | bash/ai-curl.sh

    # 编解码互逆测试
    cat chat.md | ai-chat.pl --encode | ai-chat.pl --decode

=head1 DESCRIPTION

解析遵循 docs/chat-format.md 规范的 markdown 聊天文件，提取对话内容，
合并到 JSON 模板的 messages 数组中，通过 curl 调用 API，将响应写回文件
或打印到标准输出。

=head1 OPTIONS

=over 4

=item B<--env> I<file>

指定 env 文件路径，按优先级搜索 ai-curl.env。

=item B<--url>, B<--key>, B<--model>

直接指定 API URL/Key/模型，优先级高于 env 文件。

=item B<--system> [I<msg>]

system 消息内容；以 C<@file> 形式读取文件；不带参数或空参数时
抑止自动查找 ai-chat.sys。

=item B<-i>, B<--inplace>

原位修改输入 .md 文件，将回复追加到文件末尾。隐含 C<--header>。
若从 STDIN 读取，则先复制输入到 STDOUT 再追加响应。

=item B<--header>

在响应内容前打印 C<## role E<gt>E<gt>> 标题行。

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
