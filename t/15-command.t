use strict;
use warnings FATAL => 'all';

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Dist::Zilla::App::Tester;
use Path::Tiny;
use File::pushd 'pushd';
use Moose::Util 'find_meta';
use Dist::Zilla::App::Command::stale;   # load this now, before we change directories

use lib 't/lib';
use NoNetworkHits;

{
    use Dist::Zilla::Plugin::PromptIfStale;
    my $meta = find_meta('Dist::Zilla::Plugin::PromptIfStale');
    $meta->make_mutable;
    $meta->add_around_method_modifier(_indexed_version => sub {
        my $orig = shift;
        my $self = shift;
        my ($module) = @_;

        return version->parse('200.0') if $module eq 'Indexed::But::Not::Installed';
        return undef if $module eq 'Unindexed';
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
            [ 'PromptIfStale' => 'config0' => {
                    modules => [ 'Indexed::But::Not::Installed', 'Unindexed' ],
                }
            ],

            do {
                my $mod = '0';
                map {
                    my $phase = $_;
                    map {
                        [ 'Prereqs' => $phase . $_ => { 'Foo' . $mod++ => 0 } ]
                    } qw(Requires Recommends Suggests)
                } qw(Runtime Test Develop);
            },
            [ 'PromptIfStale' => 'config1' => {
                    check_all_prereqs => 1,
                    # some of these are duplicated with prereqs
                    module => [ 'Bar', map { 'Foo' . $_ } 0 .. 2 ], phase => 'build'
                },
            ],
        )
    );

    my $result = test_dzil('.', [ 'stale' ]);

    is($result->exit_code, 0, 'dzil would have exited 0');
    is($result->error, undef, 'no errors');
    is(
        $result->output,
        join("\n",
            'Bar',
            (map { 'Foo' . $_ } ('0' .. '8')),
            'Indexed::But::Not::Installed',
            'Unindexed',
        ) . "\n",
        'stale modules and prereqs found, as configured in all PromptIfStale plugins',
    );

    diag 'got result', explain $result
        if not Test::Builder->new->is_passing;
}

done_testing;
