#!/usr/bin/perl -w
use Test::More;
use Perfect::Hash;

my @methods = sort keys %Perfect::Hash::algo_methods;
plan tests => 2*scalar(@methods);

my $dict = "examples/words20";
for my $m (map {"-$_"} @methods) {
  my $ph = new Perfect::Hash $dict, $m, '-no-false-positives';
  unless ($ph) {
    ok(1, "SKIP empty phash $m");
    ok(1, "SKIP empty phash $m");
    next;
  }
  my $w = 'good';
  my $v = $ph->perfecthash($w);
  if ($ph->false_positives) {
    # this really should not happen!
    ok($v >= 0, "method $m with ignored -no-false-positives '$w' => $v");
  } else {
    ok(!defined $v, "method $m with -no-false-positives '$w' => undef");
  }

  my $ph1 = new Perfect::Hash $dict, $m;
  $v = $ph1->perfecthash($w);
  if ($ph1->false_positives) {
    ok($v >= 0, "method $m with false_positives '$w' => $v");
  } else {
    ok(!defined $v, "method $m without false_positives '$w' => $v");
  }
}
