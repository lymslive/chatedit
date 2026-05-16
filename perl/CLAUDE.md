# Perl 代码风格规范

本目录下 Perl 代码遵循以下风格约定。

## 函数大括号：Allman 风格

`sub` 函数的开大括号**另起一行**，位于行首：

```perl
# 正确
sub my_function
{
    my ($arg) = @_;
    ...
}

# 错误（不符合本项目规范）
sub my_function {
    ...
}
```

这样 vim 用户可以用 `[[` / `]]` 在函数间跳转。

## 全局变量用 `our`

模块级可供测试文件覆盖的变量用 `our` 声明：

```perl
our $opt_debug = 0;
our $prog_name = basename($0, '.pl');
```

## 可选选项默认值

命令行选项对应变量：
- 需要自动查找配置文件时，默认值为 `undef`（表示"未指定，执行自动搜索"）
- 命令行明确传入值时（包括空字符串 `''`），跳过自动搜索
- `undef` 以外的任何值（含 `''` 和 `0`）均视为"已指定，不搜索"

```perl
our $opt_env      = undef;   # undef=自动搜索，非undef=直接使用
our $opt_template = undef;
our $opt_system   = undef;   # undef=自动搜索，''=抑止，其他=使用该值
```

## 测试 mock 方式

覆盖子函数用 Perl 符号表，无需额外模块：

```perl
no warnings 'redefine';
local *main::call_api = sub { return $canned_response_json };
```

## 测试文件位置

单元测试放在 `perl/t/`，使用 `Test::More`（随 Perl 5.14+ 内置）。运行：

```bash
prove perl/t/
```
