use strict;
use warnings FATAL => 'all';

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Fatal;
use Test::Deep;
use Path::Tiny;
use Moose::Util 'find_meta';

use lib 't/lib';
use NoNetworkHits;

my @modules_queried;
{
    use Dist::Zilla::Plugin::PromptIfStale;
    use Dist::Zilla::App::Command::stale;
    my $meta = find_meta('Dist::Zilla::Plugin::PromptIfStale');
    $meta->make_mutable;
    $meta->add_around_method_modifier(_indexed_version => sub {
        my $orig = shift;
        my $self = shift;
        my ($module) = @_;

        push @modules_queried, $module;
        return version->parse('0');
    });
}


my @prompts;
{
    my $meta = find_meta('Dist::Zilla::Chrome::Test');
    $meta->make_mutable;
    $meta->add_before_method_modifier(prompt_str => sub {
        my ($self, $prompt, $arg) = @_;
        push @prompts, $prompt;
    });
}

my $checked_app;
BUILD:
my $tzil = Builder->from_config(
    { dist_root => 't/does-not-exist' },
    {
        add_files => {
            'source/dist.ini' => simple_ini(
                [ GatherDir => ],
                [ Prereqs => RuntimeRequires => { strict => 0, DoesNotExist => 0 } ],
                [ 'PromptIfStale' => {
                        phase => 'build',
                        check_all_plugins => 1,
                        check_all_prereqs => 1,
                        modules => [ qw(NotMeEither warnings) ],
                        skip => [ qw(DoesNotExist Dist::Zilla::Plugin::Prereqs NotMeEither) ],
                    },
                ],
            ),
            path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
        },
    },
);

if (not $checked_app++)
{
    my $wd = File::pushd::pushd($tzil->root);
    cmp_deeply(
        [ Dist::Zilla::App::Command::stale->stale_modules($tzil) ],
        [ ],
        'app finds no stale modules',
    );
    @modules_queried = ();
    Dist::Zilla::Plugin::PromptIfStale::__clear_already_checked();
    goto BUILD;
}

$tzil->chrome->logger->set_debug(1);

is(
    exception { $tzil->build },
    undef,
    'build was not halted - there were no prompts',
);

is(scalar @prompts, 0, 'there were no prompts') or diag 'got: ', explain \@prompts;

my $build_dir = path($tzil->tempdir)->child('build');

my @expected_checked = (qw(strict warnings), map { 'Dist::Zilla::Plugin::' . $_ } qw(GatherDir PromptIfStale FinderCode));

cmp_deeply(
    $tzil->log_messages,
    superbagof(
        (map { re(qr/^\Q[PromptIfStale] comparing indexed vs. local version for $_: indexed=0; local version=\E/) } @expected_checked),
        re(qr/^\Q[DZ] writing DZT-Sample in /),
    ),
    'build completed successfully',
) or diag 'got: ', explain $tzil->log_messages;

cmp_deeply(
    \@modules_queried,
    bag(@expected_checked),
    'all modules, from both configs, are checked',
);

done_testing;
