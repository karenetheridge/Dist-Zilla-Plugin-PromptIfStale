use strict;
use warnings FATAL => 'all';

use Test::More;
use Test::Warnings;
use Test::DZil;
use Test::Fatal;
use Path::Tiny;

SKIP: {
    skip('this test can always be expected to work only for the author', 1)
        unless $ENV{AUTHOR_TESTING};

    skip('this test can only be run from a dzil build dir (plugin needs a version)', 1)
        if -d '.git';

    my $tzil = Builder->from_config(
        { dist_root => 't/does-not-exist' },
        {
            add_files => {
                'source/dist.ini' => simple_ini(
                    [ GatherDir => ],
                    [ 'PromptIfStale' => { modules => [ 'Dist::Zilla::Plugin::PromptIfStale' ], phase => 'build' } ],
                ),
                path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
            },
        },
    );

    # if a response has not been configured for a particular prompt, we will die
    is(
        exception { $tzil->build },
        undef,
        'no prompts when checking for a module that is not stale',
    );
}

done_testing;
