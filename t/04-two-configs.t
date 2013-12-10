use strict;
use warnings FATAL => 'all';

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Fatal;
use Path::Tiny;
use Test::Deep;
use Moose::Util 'find_meta';
use version;

use lib 't/lib';
use NoNetworkHits;

my $tzil = Builder->from_config(
    { dist_root => 't/does-not-exist' },
    {
        add_files => {
            'source/dist.ini' => simple_ini(
                [ GatherDir => ],
                [ 'PromptIfStale' => { modules => [ 'strict' ], check_all_plugins => 1, phase => 'build' } ],
            ),
            path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
        },
    },
);

my @prompts;
{
    my $meta = find_meta('Dist::Zilla::Chrome::Test');
    $meta->make_mutable;
    $meta->add_before_method_modifier(prompt_str => sub {
        my ($self, $prompt, $arg) = @_;
        push @prompts, $prompt;
    });
}

my @modules_queried;
{
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

$tzil->chrome->logger->set_debug(1);

# we will die if we are prompted
is(
    exception { $tzil->build },
    undef,
    'build succeeded when checking for a module that is not stale',
);

is(scalar @prompts, 0, 'there were no prompts') or diag 'got: ', explain \@prompts;

my $build_dir = $tzil->tempdir->subdir('build');
cmp_deeply(
    $tzil->log_messages,
    superbagof(
        (map { re(qr/^\Q[PromptIfStale] comparing indexed vs. local version for Dist::Zilla::Plugin::$_: indexed=0; local version=\E/) } qw(GatherDir PromptIfStale)),
        '[DZ] writing DZT-Sample in ' . $build_dir,
    ),
    'build completed successfully',
) or diag 'got: ', explain $tzil->log_messages;

cmp_deeply(
    \@modules_queried,
    bag('strict', map { 'Dist::Zilla::Plugin::' . $_ } qw(GatherDir PromptIfStale FinderCode)),
    'all modules, from both configs, are checked',
);

done_testing;
