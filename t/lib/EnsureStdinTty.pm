use strict;
use warnings FATAL => 'all';

# do not release before global destruction
my $pty;

if (not -t STDIN)
{
    if ($^O ne 'MSWin32')
    {
        # make these tests work even if stdin is not a tty

        # not sure if this is a bug, but on some platforms, if we do not
        # explicitly close STDIN first, when it is closed (via open) the pty
        # is closed as well
        close STDIN;

        require IO::Pty;
        $pty = IO::Pty->new;
        STDIN->fdopen($pty->slave, '<')
            or die "could not connect stdin to a pty: $!";

        $TODO = 'on perls <5.16, IO::Pty may not work on all platforms'
            if $] < 5.016;
    }
    else {
        ::plan skip_all => 'cannot run these tests on MSWin32 when stdin is not a tty';
    }
}

END {
    ::diag 'status of filehandles: ', ::explain +{
        '-t STDIN' => -t STDIN,
        '-t STDOUT' => -t STDOUT,
        '-f STDOUT' => -f STDOUT,
        '-c STDOUT' => -c STDOUT,
    } if not Test::Builder->new->is_passing;
}

1;
