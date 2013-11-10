use strict;
use warnings FATAL => 'all';

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Fatal;
use Test::Deep;
use File::Spec;
use Path::Tiny;
use Moose::Util 'find_meta';

BEGIN {
    use Dist::Zilla::Plugin::PromptIfStale;
    $Dist::Zilla::Plugin::PromptIfStale::VERSION = 9999
        unless $Dist::Zilla::Plugin::PromptIfStale::VERSION;
}

my @checked_via_02packages;
{
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
    skip('this test downloads a large file from the CPAN and should only be run for authors', 1)
        unless $ENV{AUTHOR_TESTING} or -d '.git';

    subtest 'testing against real index on the network...' => \&do_tests;
}

# ensure we don't actually make network hits
{
    use HTTP::Tiny;
    my $meta = find_meta('HTTP::Tiny')
        || Class::MOP::Class->initialize('HTTP::Tiny');
    $meta->add_around_method_modifier(mirror => sub { +{ success => 1 } });
}
{
    use Parse::CPAN::Packages::Fast;
    my $meta = find_meta('Parse::CPAN::Packages::Fast')
        || Class::MOP::Class->initialize('Parse::CPAN::Packages::Fast');
    my $initialized;
    $meta->add_around_method_modifier(new => sub {
        die if $initialized;
        'fake packages object ' . $initialized++;
    });
}

subtest 'testing against a faked index...' => \&do_tests;

done_testing;

sub do_tests
{
    @checked_via_02packages = @prompts = ();
    Dist::Zilla::Plugin::PromptIfStale::__clear_already_checked();

    my $tzil = Builder->from_config(
        { dist_root => 't/does-not-exist' },
        {
            add_files => {
                'source/dist.ini' => simple_ini(
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
            also_copy => { 't/lib' => 't/lib' },
        },
    );

    # no need to test all combinations - we sort the module list
    my $prompt0 = "Issues found:\n"
        . join("\n", map { '    Unindexed' . $_ . ' is not indexed.' } 0..5)
        . "\nContinue anyway?";
    $tzil->chrome->set_response_for($prompt0, 'y');

    my $prompt1 = 'Unindexed6 is not indexed. Continue anyway?';
    $tzil->chrome->set_response_for($prompt1, 'n');

    $tzil->chrome->logger->set_debug(1);

    local @INC = @INC;
    unshift @INC, File::Spec->catdir($tzil->tempdir, qw(t lib));

    like(
        exception { $tzil->build },
        qr/\Q[PromptIfStale] Aborting build\E/,
        'build aborted',
    );

    cmp_deeply(
        \@prompts,
        [ $prompt0, $prompt1 ],
        'we were indeed prompted',
    );

    cmp_deeply(
        \@checked_via_02packages,
        [ map { 'Unindexed' . $_ } 0..6 ],
        'all modules checked using 02packages',
    );

    cmp_deeply(
        $tzil->log_messages,
        supersetof("[PromptIfStale] Aborting build\n[PromptIfStale] To remedy, do: cpanm Unindexed6"),
        'build was aborted, with remedy instructions',
    ) or diag 'got: ', explain $tzil->log_messages;
}
