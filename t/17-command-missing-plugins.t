use strict;
use warnings FATAL => 'all';

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Dist::Zilla::App::Tester;
use Path::Tiny;
use File::pushd 'pushd';
use Dist::Zilla::App::Command::stale;   # load this now, before we change directories

use lib 't/lib';
use NoNetworkHits;

{
    local $ENV{DZIL_GLOBAL_CONFIG_ROOT} = 'does-not-exist';

    # TODO: we should be able to call a sub that specifies our corpus layout
    # including dist.ini, rather than having to build it ourselves, here.
    # This would also help us improve the tests for the 'authordeps' command.

    my $tempdir = Path::Tiny->tempdir(CLEANUP => 1);
    my $root = $tempdir->child('source');
    $root->mkpath;
    my $wd = pushd $root;
    path($root, 'dist.ini')->spew_utf8(simple_ini([ NonexistentPlugin => ]));

    my $result = test_dzil('.', [ 'stale' ]);

    is($result->exit_code, 0, 'dzil would have exited 0');
    is($result->error, undef, 'no errors');
    is($result->output, "Dist::Zilla::Plugin::NonexistentPlugin\n", 'dzil authordeps ran to get missing plugins');

    diag 'got result: ', explain $result
        if not Test::Builder->new->is_passing;
}

done_testing;
