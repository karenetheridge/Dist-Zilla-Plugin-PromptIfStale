use strict;
use warnings FATAL => 'all';

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Fatal;
use Test::Deep;
use Path::Tiny;
use Moose::Util 'find_meta';
use List::Util 'first';

use lib 't/lib';
use NoNetworkHits;

my @modules_queried;
{
    use Dist::Zilla::Plugin::PromptIfStale;
    my $meta = find_meta('Dist::Zilla::Plugin::PromptIfStale');
    $meta->make_mutable;
    $meta->add_around_method_modifier(_indexed_version => sub {
        my $orig = shift;
        my $self = shift;
        my ($module) = @_;

        push @modules_queried, $module;
        return version->parse($module eq 'Carp' ? '2000' : '0');
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
                        skip_core_modules => 1,
                        modules => [ qw(Carp NotMeEither warnings) ],
                        skip => [ qw(DoesNotExist Dist::Zilla::Plugin::Prereqs NotMeEither) ],
                    },
                ],
            ),
            path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
        },
    },
);

$tzil->chrome->logger->set_debug(1);

is(
    exception { $tzil->build },
    undef,
    'build was not halted - there were no prompts',
);

is(scalar @prompts, 0, 'there were no prompts') or diag 'got: ', explain \@prompts;

my $build_dir = $tzil->tempdir->subdir('build');

my @expected_checked = (map { 'Dist::Zilla::Plugin::' . $_ } qw(GatherDir PromptIfStale FinderCode));

cmp_deeply(
    $tzil->log_messages,
    superbagof(
        (map { re(qr/^\Q[PromptIfStale] comparing indexed vs. local version for $_: indexed=0; local version=\E/) } @expected_checked),
        '[DZ] writing DZT-Sample in ' . $build_dir,
    ),
    'build completed successfully',
) or diag 'got: ', explain $tzil->log_messages;

cmp_deeply(
    \@modules_queried,
    bag(@expected_checked),
    'all modules, from both configs, are checked',
);

done_testing;

