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

# for non-author tests, we also patch HTTP::Tiny and
# Parse::CPAN::Packages::Fast so we don't actually make network hits

my @prompts;
{
#    use Dist::Zilla::Chrome::Test;
    my $meta = find_meta('Dist::Zilla::Chrome::Test');
    $meta->make_mutable;
    $meta->add_before_method_modifier(prompt_str => sub {
        my ($self, $prompt, $arg) = @_;
        push @prompts, $prompt;
    });
}


SKIP: {
    skip('this test downloads a large file from the CPAN and usually should only be run for authors', 1)
        unless $ENV{AUTHOR_TESTING} or $ENV{EXTENDED_TESTING} or -d '.git';

    subtest 'testing against real index on the network...' => \&do_tests;
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

subtest 'testing against a faked index...' => \&do_tests;

done_testing;

sub do_tests
{
    @checked_via_02packages = @prompts = ();
    Dist::Zilla::Plugin::PromptIfStale::__clear_already_checked();

    my $checked_app;
    BUILD:
    my $tzil = Builder->from_config(
        { dist_root => 't/does-not-exist' },
        {
            add_files => {
                path(qw(source dist.ini)) => simple_ini(
                    [ GatherDir => ],
                    [ PromptIfStale => {
                        modules => [ map { 'Unindexed' . $_ } 0..5 ],
                        check_all_prereqs => 1,
                        phase => 'build',
                      } ],
                    [ Prereqs => RuntimeRequires => { 'Unindexed6' => 0 } ],
                ),
                path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
            },
            also_copy => { 't/corpus' => 't/lib' },
        },
    );

    # no need to test all combinations - we sort the module list
    my $prompt0 = "6 stale modules found, continue anyway?";
    $tzil->chrome->set_response_for($prompt0, 'n');

    # ensure we find the library, not in a local directory, before we change directories
    local @INC = @INC;
    unshift @INC, path($tzil->tempdir, qw(t lib))->stringify;

    if (not $checked_app++)
    {
        my $wd = pushd $tzil->root;
        cmp_deeply(
            [ Dist::Zilla::App::Command::stale->stale_modules($tzil) ],
            [ map { 'Unindexed' . $_ } 0..6 ],
            'app finds stale modules',
        );
        @checked_via_02packages = ();
        Dist::Zilla::Plugin::PromptIfStale::__clear_already_checked();
        goto BUILD;
    }

    $tzil->chrome->logger->set_debug(1);

    like(
        exception { $tzil->build },
        qr/\Q[PromptIfStale] Aborting build\E/,
        'build aborted',
    );

    cmp_deeply(
        \@prompts,
        [ $prompt0 ],
        'we were indeed prompted',
    );

    cmp_deeply(
        \@checked_via_02packages,
        [ map { 'Unindexed' . $_ } 0..5 ],
        'all modules checked using 02packages',
    );

    like($http_url, qr{^http://www.cpan.org/}, 'regular CPAN index URL used');

    cmp_deeply(
        $tzil->log_messages,
        superbagof("[PromptIfStale] Aborting build due to stale modules!"),
        'build was aborted, with remedy instructions',
    );

    diag 'got log messages: ', explain $tzil->log_messages
        if not Test::Builder->new->is_passing;
}
