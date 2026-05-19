#!/usr/bin/env perl
# 测试 open_stdin：stdin 缓冲到临时文件，--append 时同步复制到 stdout
use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);

require "$Bin/../ai-chat.pl";

# 抑止 system 文件查找
{
    no warnings 'once';
    $main::opt_system = '';
}

# ============================================================================
# 场景 1：不带 --append，STDIN 写入临时文件，stdout 不输出
# ============================================================================
{
    my $input = "## user >>\n\nHello stdin\n";

    {
        no warnings 'once';
        $main::opt_append = 0;
    }

    my $stdout = '';
    my $fh;
    {
        local *STDIN;
        open STDIN, '<:raw', \$input or die "cannot open STDIN: $!";

        local *STDOUT;
        open STDOUT, '>:raw', \$stdout or die "cannot open STDOUT: $!";

        $fh = open_stdin();
    }

    local $/;
    my $got = <$fh>;
    close $fh;

    is( $got,    $input, 'open_stdin(no append): tmp file content matches STDIN' );
    is( $stdout, '',     'open_stdin(no append): nothing written to stdout' );
}

# ============================================================================
# 场景 2：带 --append，STDIN 写入临时文件，且同步复制到 stdout
# ============================================================================
{
    my $input = "## user >>\n\nHello with append\n";

    {
        no warnings 'once';
        $main::opt_append = 1;
    }

    my $stdout = '';
    my $fh;
    {
        local *STDIN;
        open STDIN, '<:raw', \$input or die "cannot open STDIN: $!";

        local *STDOUT;
        open STDOUT, '>:raw', \$stdout or die "cannot open STDOUT: $!";

        $fh = open_stdin();
    }

    local $/;
    my $got = <$fh>;
    close $fh;

    is( $got, $input, 'open_stdin(append): tmp file content matches STDIN' );
    like( $stdout, qr/Hello with append/, 'open_stdin(append): STDIN content copied to stdout' );

    # 恢复
    no warnings 'once';
    $main::opt_append = 0;
}

# ============================================================================
# 场景 3：--append 时，STDIN 末尾无换行 → stdout 末尾补 \n
# ============================================================================
{
    my $input = "no trailing newline";

    {
        no warnings 'once';
        $main::opt_append = 1;
    }

    my $stdout = '';
    my $fh;
    {
        local *STDIN;
        open STDIN, '<:raw', \$input or die "cannot open STDIN: $!";

        local *STDOUT;
        open STDOUT, '>:raw', \$stdout or die "cannot open STDOUT: $!";

        $fh = open_stdin();
    }

    close $fh;

    like( $stdout, qr/no trailing newline\n$/, 'open_stdin(append,no newline): stdout ends with \n' );

    # 恢复
    no warnings 'once';
    $main::opt_append = 0;
}

done_testing();
