#!/usr/bin/perl -w
use Test::More;
use Perfect::Hash;

use lib 't';
require "test.pl";

my ($default, $methods, $opts) = test_parse_args("-nul");

plan tests => 5 * scalar(@$methods);
my ($dict, $dictarr, $size, $custom_size) = opt_dict_size($opts, "examples/words500");
my $small_dict = $size > 255 ? "examples/words20" : $dict;

# CHM passes pure-perl, but not compiled yet
$Perfect::Hash::algo_todo{'-cmph-chm'} = 1;
$Perfect::Hash::algo_todo{'-bob'} = 1;
$Perfect::Hash::algo_todo{'-pearson16'} = 1;

my $i = 0;
my $key = "AOL";

for my $m (@$methods) {
  my $used_dict = $m eq '-pearson8'
    ? $small_dict
    : ($m eq '-gperf' or $custom_size)
      ? $dictarr
      : $dict;
  my $ph = new Perfect::Hash($used_dict, $m, @$opts, "-nul");
  unless ($ph) {
    ok(1, "SKIP empty pperf $m");
    ok(1) for 1..4;
    $i++;
    next;
  }
  if ($m =~ /^-cmph/) {
    ok(1, "SKIP nyi save_c for $m");
    ok(1) for 1..4;
    $i++;
    next;
  }
  my $suffix = $m eq "-bob" ? "_hash" : "_nul";
  my $base = "pperf$suffix";
  my $out = "$base.c";
  test_wmain($m, 1, $key, $ph->perfecthash($key), $suffix, 1);
  $i++;
  $ph->save_c($base);
  if (ok(-f "$base.c" && -f "$base.h", "$m generated $base.c/.h")) {
    my $cmd = compile_static($ph, $suffix);
    diag($cmd) if $ENV{TEST_VERBOSE};
    my $retval = system($cmd);
    if (ok(!($retval>>8), "could compile $m")) {
      my $retstr = $^O eq 'MSWin32' ? `$base` : `./$base`;
      $retval = $?;
      TODO: {
        local $TODO = "$m" if exists $Perfect::Hash::algo_todo{$m} and $m !~ /^-cmph/;
        like($retstr, qr/^ok - c lookup exists/m, "$m c lookup exists");
      }
      TODO: {
        local $TODO = "$m" if exists $Perfect::Hash::algo_todo{$m};
        like($retstr, qr/^ok - c lookup notexists/m, "$m c lookup notexists");
      }
    } else {
      ok(1, "SKIP") for 1..2;
    }
    TODO: {
      local $TODO = "$m" if exists $Perfect::Hash::algo_todo{$m}; # will return errcodes
      ok(!($retval>>8), "could run $m");
    }
  } else {
    ok(1, "SKIP") for 1..3;
  }
  unlink("$base","$base.c","$base.h","main$suffix.c") if $default;
}
