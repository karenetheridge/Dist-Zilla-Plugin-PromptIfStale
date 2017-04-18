use strict;
use warnings;

# Thanks to the changes in 0.025, code now behaves differently depending on
# the state of our filehandles. We test here that we are indeed forcing stdin
# to a pty in all tests that need it, by forcing it closed up front and then
# unleashing the hounds. This simulates installing the module with stdin not
# using a tty, as in 'cpan-outdated | cpanm' or 'dzil listdeps | cpanm'.

use Test::More 0.96;
use Test::Warnings;
use File::Spec;
use IO::Handle;
use IPC::Open3;

# make it look like we are running non-interactively
open my $stdin, '<', File::Spec->devnull or die "can't open devnull: $!";
my $inc_switch = -d 'blib' ? '-Mblib' : '-Ilib';

foreach my $test (glob('t/*'))
{
    next if not -f $test;
    next if $test =~ /\b00-/;
    subtest $test => sub {
        diag "running $test";
        do $test;
        note 'ran tests successfully' if not $@;
        fail($@) if $@;
    };
}

done_testing;
