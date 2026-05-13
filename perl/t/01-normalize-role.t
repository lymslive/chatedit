#!/usr/bin/env perl
# 测试 normalize_role 函数：角色名归一化
use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);

require "$Bin/../ai-chat.pl";

is( normalize_role('P'),         'system',    'P -> system' );
is( normalize_role('Q'),         'user',      'Q -> user' );
is( normalize_role('A'),         'assistant', 'A -> assistant' );
is( normalize_role('p'),         'system',    'p (lowercase) -> system' );
is( normalize_role('q'),         'user',      'q (lowercase) -> user' );
is( normalize_role('a'),         'assistant', 'a (lowercase) -> assistant' );
is( normalize_role('system'),    'system',    'system stays system' );
is( normalize_role('user'),      'user',      'user stays user' );
is( normalize_role('assistant'), 'assistant', 'assistant stays assistant' );
is( normalize_role('SYSTEM'),    'system',    'SYSTEM -> lowercased' );
is( normalize_role('USER'),      'user',      'USER -> lowercased' );
is( normalize_role('Assistant'), 'assistant', 'Assistant -> lowercased' );

done_testing();
