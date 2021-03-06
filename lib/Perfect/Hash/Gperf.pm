package Perfect::Hash::Gperf;

use strict;
our $VERSION = '0.01';
#use warnings;
use Perfect::Hash;
use Perfect::Hash::C;
#use integer;
#use bytes;
our @ISA = qw(Perfect::Hash Perfect::Hash::C);
use Config;

=head1 DESCRIPTION

Uses no hash function nor hash table, just generates a gperf
table in C<C>.

gperf is limited to a low number of keys (<50000), and is sensitive to
anagrams and bad key distributions.
We need to time out after 60 seconds.

gperf does not hash the keys, it just takes a number of distinct chars
from the key and adds them together. This is usually faster then a
full hash over the all key characters.

=head1 METHODS

=over

=item new $filename, @options

Honored options are:

-max-time  default: 60, disable with 0
-nul is always set.
-pic is disabled
-7bit
-switches => --switch=2

All other options are just passed through.

=cut

sub new { 
  my $class = shift or die;
  my $dict = shift; #hashref, arrayref or filename
  my $options = Perfect::Hash::_handle_opts(@_);
  $options->{'-nul'} = 1;
  if (!exists $options->{'-max-time'}) {
    $options->{'-max-time'} = 60;
  } elsif (!$options->{'-max-time'}) {
    delete $options->{'-max-time'};
  }
  # see if we can use the gperf executable, return undef if not
  # no PP fallback variant yet
  my $retval = system("gperf --version".($^O eq 'MSWin32' ? "" : " >/dev/null"));
  if ($retval != 0) {
    return undef;
  }

  # enforce KEYFILE
  my $fn = "pperf_keys.tmp";
  if (ref $dict eq 'ARRAY') {
    unlink $fn;
    open my $F, ">", $fn;
    print $F "%{\n#include <string.h>\n%}\n";
    print $F "%struct-type\nstruct pperf_table { char *name; const int value; };\n%%\n";
    my $i = 0;
    my %dict;
    for (@$dict) {
      print $F "$_,\t$i\n" if length($_);
      $dict{$_} = $i++;
    }
    print $F "%%";
    close $F;
    $dict = \%dict;
  }
  elsif (ref $dict eq 'HASH') {
    open my $F, ">", $fn;
    print $F "%{\n#include <string.h>\n%}\n";
    print $F "%struct-type\nstruct pperf_table { char *name; const int value; };\n%%\n";
    for (sort keys %$dict) {
      print $F "$_,\t",$dict->{$_},"\n" if length($_);
    }
    print $F "%%";
    close $F;
  } elsif (!ref $dict and ! -e $dict) {
    die "wrong dict argument. arrayref, hashref or filename expected";
  } else {
    my %hash;
    open my $d, "<", $dict or die; {
      local $/;
      my $i = 0;
      %hash = map {$_ => $i++ } split /\n/, <$d>;
    }
    close $d;
    $fn = $dict;
    $dict = \%hash;
  }
  if (!-f $fn or !-s $fn) {
    return undef;
  }
  return bless [$fn, $options, $dict], $class;
}

=item save_c fileprefix, options

Generates a $fileprefix.c file.

=cut

#our $proc; # global for the sig alrm handler

sub save_c {
  my $ph = shift;
  my ($fn, $options, $dict) = ($ph->[0], $ph->[1], $ph->[2]);
  my ($fileprefix, $base) = $ph->save_h_header(@_);
  my %opts = (
             #'-pic'      => '-P', # generates wrong code with structs
             #'-nul'      => '-l',
              '-7bit'     => '-7',
              '-switches' => '--switch=2',
             );
  my @opts = ("-l", # --compare-lengths (always use -nul)
              "-c", # --compare-strncmp
              "-C", # --readonly-tables
              "-N$base\_lookup", "-H$base\_hash");
  for (keys %$options) {
    push @opts, $opts{$_} if exists $opts{$_}; 
  }
  # since we need to redirect we need a shell
  # but if we got a shell we need to kill gperf and the shell
  my @cmd = ("gperf", @opts, $fn, ">$fileprefix.c");
  print join(" ",@cmd),"\n" if $ENV{TEST_VERBOSE};
  if ($options->{'-max-time'} and $^O =~ /linux|bsd|darwin|solaris|cygwin/) { # timeout
    use POSIX ":sys_wait_h";
    my $pid = fork;
    die "fork" if !defined $pid;
    if ($pid > 0) {
      eval {
        my $secs = 0; my $res;
        do {
          sleep ( 1 ); $secs++;
          $res = waitpid($pid, WNOHANG); # the forked perl
          warn "pid=$pid, res=$res, err=",$?,"\n" if $options->{'-debug'};
          $res = -1 if $secs >= $options->{'-max-time'};
        } while ($res == 0); # check if pid is still running or timed out
        $res = waitpid($pid, WNOHANG);
        warn "res=$res, err=",$?,"\n" if $options->{'-debug'};
        if ($res == 0) { # check if pid is still running. with exec it is not.
          kill 9, -$pid; # the group
          warn "timeout: gperf killed\n";
        }
      }
    } elsif ($pid == 0) {
      setpgrp(0, 0); # with exec sets the process status to T for stopped and traced.
      # undetectable to waitpid.
      # however with system it creates a proper detectable and killable child hierarchy.
      system(join " ", @cmd);
      exit(0);
    }
  } else {
    system(join(" ",@cmd));
  }
  my $errcode = $? >> 8;
  unlink $fn if $fn eq "pperf_keys.tmp" and !$errcode;
  return $errcode;
}

=item perfecthash $ph, $key

dummy pure-perl variant just for testing.

=cut

sub perfecthash {
  my $ph = shift;
  my $dict = $ph->[2];
  my $key = shift;
  return exists $dict->{$key} ? $dict->{$key} : undef;
}

=item false_positives

=cut

sub false_positives {}

=item option $ph

Access the option hash in $ph.

=cut

sub option {
  return $_[0]->[1]->{$_[1]};
}

=item c_lib, c_include

empty as Switch needs no external dependencies.

=cut

sub c_include { "" }

sub c_lib { "" }


sub c_funcdecl {
  my ($ph, $base) = @_;
  my $struct = "struct pperf_table";
  my $decl = "$struct {char *name; const int value; };";
  if ($ph->option('-nul')) {
    "
$decl
$struct * $base\_lookup(const char* s, int l)";
  } else {
    "
$decl
$struct * $base\_lookup(const char* s)";
  }
}



=back

=cut

1;
