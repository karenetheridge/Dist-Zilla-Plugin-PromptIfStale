
use strict;
use warnings FATAL => 'all';

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::Deep;
use Test::DZil;
use Dist::Zilla::App::Tester;
use Path::Tiny;
use File::pushd 'pushd';
use Moose::Util 'find_meta';
use Dist::Zilla::App::Command::stale;   # load this now, before we change directories
use Dist::Zilla::Plugin::PromptIfStale;

use lib 't/lib';
use NoNetworkHits;

my @modules_checked;
{
    my $meta = find_meta('Dist::Zilla::Plugin::PromptIfStale');
    $meta->make_mutable;
    $meta->add_around_method_modifier(_indexed_version => sub {
        my $orig = shift;
        my $self = shift;
        my ($module) = @_;
        push @modules_checked, $module;
        return 0 if $module =~ /^Dist::Zilla::Plugin::/;    # all plugins are current
        return 200 if $module eq 'strict';
        die 'should not be checking for ' . $module;
    });
}

{
    local $ENV{DZIL_GLOBAL_CONFIG_ROOT} = 'does-not-exist';

    # TODO: we should be able to call a sub that specifies our corpus layout
    # including dist.ini, rather than having to build it ourselves, here.
    # This would also help us improve the tests for the 'authordeps' command.

    my $tempdir = Path::Tiny->tempdir(CLEANUP => 1);
    my $root = $tempdir->child('source');
    $root->mkpath;
    my $wd = pushd $root;

    path($root, 'dist.ini')->spew_utf8(
        simple_ini(
            [ GatherDir => ],
            do {
                my $mod = '0';
                map {
                    my $phase = $_;
                    map {
                        [ 'Prereqs' => $phase . $_ => { 'Foo' . $mod++ => 0 } ]
                    } qw(Requires Recommends Suggests)
                } qw(Runtime Test Develop);
            },
        ) . "\n\n; authordep strict\n",
    );

    {
        my $result = test_dzil('.', [ 'stale' ]);

        is($result->exit_code, 0, 'dzil would have exited 0');
        is($result->error, undef, 'no errors');
        is(
            $result->output,
            "\n",
            'nothing found when no PromptIfStale plugins configured',
        );
        cmp_deeply(\@modules_checked, [], 'nothing was actually checked for');
    }

    Dist::Zilla::Plugin::PromptIfStale::__clear_already_checked();

    {
        my $result = test_dzil('.', [ 'stale', '--all' ]);

        is($result->exit_code, 0, 'dzil would have exited 0');
        is($result->error, undef, 'no errors');
        is(
            $result->output,
            join("\n", (map { 'Foo' . $_ } ('0' .. '8')), 'strict') . "\n",
            'stale prereqs and authordeps found with --all, despite no PromptIfStale plugins configured',
        );

        cmp_deeply(
            \@modules_checked,
            set( 'strict', re(qr/^Dist::Zilla::Plugin::/) ),
            'indexed versions of plugins were checked',
        );
    }
}

done_testing;
