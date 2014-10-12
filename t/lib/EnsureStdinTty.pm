use strict;
use warnings FATAL => 'all';

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
        STDIN->fdopen(IO::Pty->new->slave, '<')
            or die "could not connect stdin to a pty: $!";
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
