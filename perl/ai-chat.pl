#!/usr/bin/env perl
# ai-chat.pl - 将 markdown 聊天文件转换为 AI API 的 JSON 请求体

use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use JSON::PP;

# ---- 选项解析 ---------------------------------------------------------------

my $opt_template = '';
my $opt_debug    = 0;
my $opt_help     = 0;

GetOptions(
    'template|t=s' => \$opt_template,
    'debug|d'      => \$opt_debug,
    'help|h'       => \$opt_help,
) or do { usage(); exit 1 };

if ($opt_help) { usage(); exit 0 }

# ---- 主流程 -----------------------------------------------------------------

my $template = load_template();
my $fh       = open_input();
my @messages = parse_chat($fh);
close $fh;

if ($opt_debug) {
    warn "[debug] 解析到 " . scalar(@messages) . " 条 message\n";
    for my $i (0 .. $#messages) {
        my $m = $messages[$i];
        warn "[debug] message[$i] role=$m->{role} content_len=" . length($m->{content}) . "\n";
    }
}

$template->{messages} = \@messages;

my $json = JSON::PP->new->utf8->pretty->canonical(0);
print $json->encode($template);

# ---- 子函数 -----------------------------------------------------------------

# 打开输入文件句柄（命令行参数文件或 STDIN）
sub open_input {
    if (@ARGV) {
        my $file = shift @ARGV;
        open my $fh, '<:utf8', $file
            or die "错误: 无法打开文件 '$file': $!\n";
        warn "[debug] 输入文件: $file\n" if $opt_debug;
        return $fh;
    }
    else {
        warn "[debug] 从 STDIN 读取输入\n" if $opt_debug;
        binmode STDIN, ':utf8';
        return \*STDIN;
    }
}

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

将 markdown 聊天文件解析并转换为 AI API 的 JSON 请求体，输出到标准输出。
可与 ai-curl.sh 联用：

    cat chat.md | perl/ai-chat.pl | bash/ai-curl.sh

选项:
  -t, --template <file>  指定 JSON 模板文件（默认按优先级搜索）
  -d, --debug            打印调试信息到 stderr
  -h, --help             显示此帮助

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

ai-chat.pl - 将 markdown 聊天文件转换为 AI API 的 JSON 请求体

=head1 SYNOPSIS

    ai-chat.pl [选项] [input.md]
    ai-chat.pl [选项] < input.md

    # 联用 ai-curl.sh 直接调用 API
    cat chat.md | perl/ai-chat.pl | bash/ai-curl.sh

=head1 DESCRIPTION

解析遵循 docs/chat-format.md 规范的 markdown 聊天文件，提取对话内容，
合并到 JSON 模板的 messages 数组中，输出完整的 API 请求 JSON。

支持的 markdown 格式：

=over 4

=item C<## role E<gt>E<gt>> 对话段

role 可为 system/user/assistant 或缩写 P/Q/A。
C<E<gt>E<gt>> 后的内容为第一行，续行继续积累至下一个对话段或注释段。

=item C<# > 注释行

一级标题（C<# >）开头的行视为注释，结束当前对话段。

=item C<@file> 引入文件

在对话段（C<## role E<gt>E<gt>>）内以 C<@> 开头的行，将指定文件内容插入当前 message。
读取失败时输出原行并附加 C<(Read Error)>，无内容或仅空白时附加 C<(Read Empty)>。

=item C<!cmd> 执行命令

在对话段（C<## role E<gt>E<gt>>）内以 C<!> 开头的行，执行 shell 命令，将标准输出插入当前 message。
命令失败（非零退出码）时输出原行并附加 C<(Read Error)>，无输出或仅空白时附加 C<(Read Empty)>。

=item 代码块

三反引号 C<```> 括起的代码块内，忽略以上所有特殊标记。

=back

=head1 OPTIONS

=over 4

=item B<-t>, B<--template> I<file>

指定 JSON 模板文件。模板中的 C<messages> 字段会被解析内容替换。

=item B<-d>, B<--debug>

将调试信息输出到标准错误。

=item B<-h>, B<--help>

显示帮助信息。

=back

=head1 TEMPLATE SEARCH ORDER

=over 4

=item 1. C<--template> 选项指定的文件

=item 2. C<./ai-chat.json>

=item 3. C<./.chatedit/ai-chat.json>

=item 4. C<~/.chatedit/ai-chat.json>

=item 5. 内联固定模板（C<{"model":"$API_MODEL","messages":[]}>）

=back

=head1 AUTHOR

lymslive

=cut
