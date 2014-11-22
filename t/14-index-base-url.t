use strict;
use warnings FATAL => 'all';

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Fatal;
use Test::Deep;
use Path::Tiny;
use Moose::Util 'find_meta';
use File::pushd 'pushd';
use Dist::Zilla::App::Command::stale;

use lib 't/lib';
use NoNetworkHits;
use EnsureStdinTty;

my @checked_via_02packages;
{
    use Dist::Zilla::Plugin::PromptIfStale;
    my $meta = find_meta('Dist::Zilla::Plugin::PromptIfStale');
    $meta->make_mutable;
    $meta->add_around_method_modifier(_indexed_version_via_query => sub {
        my $orig = shift;
        my $self = shift;
        my ($module) = @_;
        die 'should not be checking for ' . $module;
    });
    $meta->add_around_method_modifier(_indexed_version_via_02packages => sub {
        my $orig = shift;
        my $self = shift;
        my ($module) = @_;

        $self->_get_packages;   # force this to be initialized in the class
        push(@checked_via_02packages, $module), return undef if $module =~ /^Unindexed[0-6]$/;
        die 'should not be checking for ' . $module;
    });
    my $packages;
}

# ensure we don't actually make network hits
my $http_url;
{
    use HTTP::Tiny;
    package HTTP::Tiny;
    no warnings 'redefine';
    sub mirror { $http_url = $_[1]; +{ success => 1 } }
}
{
    use Parse::CPAN::Packages::Fast;
    package Parse::CPAN::Packages::Fast;
    my $initialized;
    no warnings 'redefine';
    sub new {
        die if $initialized;
        'fake packages object ' . $initialized++;
    }
}

{
    my $tzil = Builder->from_config(
        { dist_root => 't/does-not-exist' },
        {
            add_files => {
                path(qw(source dist.ini)) => simple_ini(
                    [ GatherDir => ],
                    [ PromptIfStale => {
                        modules => [ map { 'Unindexed' . $_ } 0..5 ],
                        phase => 'build',
                        index_base_url => 'http://gettysworld.org',
                        fatal => 1,
                      } ],
                ),
                path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
            },
            also_copy => { 't/corpus' => 't/lib' },
        },
    );

    {
        my $wd = pushd $tzil->root;
        cmp_deeply(
            [ Dist::Zilla::App::Command::stale->stale_modules($tzil) ],
            [ map { 'Unindexed' . $_ } 0..5 ],
            'app finds no stale modules',
        );
        Dist::Zilla::Plugin::PromptIfStale::__clear_already_checked();
    }

    # ensure we find the library, not in a local directory, before we change directories
    local @INC = @INC;
    unshift @INC, path($tzil->tempdir, qw(t lib))->stringify;

    $tzil->chrome->logger->set_debug(1);

    like(
        exception { $tzil->build },
        qr/\Q[PromptIfStale] Aborting build\E/,
        'build aborted',
    );

    cmp_deeply(
        \@checked_via_02packages,
        [ map { 'Unindexed' . $_ } 0..5 ],
        'all modules checked using 02packages',
    );

    like($http_url, qr{^http://gettysworld.org/}, 'overridden index URL used');

    cmp_deeply(
        $tzil->log_messages,
        superbagof(
            (map { '[PromptIfStale] Unindexed' . $_ . ' is not indexed.' } 0..5),
            "[PromptIfStale] Aborting build due to stale modules!"
        ),
        'build was aborted, with remedy instructions',
    );

    diag 'got log messages: ', explain $tzil->log_messages
        if not Test::Builder->new->is_passing;
}

done_testing;
