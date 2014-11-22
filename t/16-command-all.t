
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

use lib 't/lib';
use NoNetworkHits;

my @modules_checked;
{
    use Dist::Zilla::Plugin::PromptIfStale;
    my $meta = find_meta('Dist::Zilla::Plugin::PromptIfStale');
    $meta->make_mutable;
    $meta->add_around_method_modifier(_indexed_version => sub {
        my $orig = shift;
        my $self = shift;
        my ($module) = @_;
        push @modules_checked, $module;
        return 0 if $module =~ /^Dist::Zilla::Plugin::/;    # all plugins are current
        return 200 if $module eq 'Carp';
        die 'should not be checking for ' . $module;
    });
    $meta->add_around_method_modifier(_is_duallifed => sub {
        my $orig = shift;
        my $self = shift;
        my ($module) = @_;

        return 1 if $module eq 'Carp';
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
        ) . "\n\n; authordep Carp\n",
    );

    {
        my $result = test_dzil('.', [ 'stale' ]);

        is($result->exit_code, 0, 'dzil would have exited 0');
        is($result->error, undef, 'no errors');
        is(
            $result->stdout,
            "\n",
            'nothing found when no PromptIfStale plugins configured',
        );
        cmp_deeply(\@modules_checked, [], 'nothing was actually checked for');

        diag 'got stderr output: ' . $result->stderr
            if $result->stderr;
    }

    Dist::Zilla::Plugin::PromptIfStale::__clear_already_checked();

    {
        my $result = test_dzil('.', [ 'stale', '--all' ]);

        is($result->exit_code, 0, 'dzil would have exited 0');
        is($result->error, undef, 'no errors');
        is(
            $result->output,
            join("\n", 'Carp', (map { 'Foo' . $_ } ('0' .. '8'))) . "\n",
            'stale prereqs and authordeps found with --all, despite no PromptIfStale plugins configured',
        );

        cmp_deeply(
            \@modules_checked,
            set( 'Carp', re(qr/^Dist::Zilla::Plugin::/) ),
            'indexed versions of plugins were checked',
        ) or diag 'checked modules: ', explain \@modules_checked;

        diag 'got result: ', explain $result
            if not Test::Builder->new->is_passing;
    }
}

done_testing;
