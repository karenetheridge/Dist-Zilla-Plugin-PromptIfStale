use strict;
use warnings FATAL => 'all';

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Fatal;
use Test::Deep;
use Path::Tiny;
use Moose::Util 'find_meta';
use File::Spec;
use Dist::Zilla::App::Command::stale;

use lib 't/lib';
use NoNetworkHits;

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
                [ 'PromptIfStale' => { modules => [ 'Unindexed' ], phase => 'build' } ],
            ),
            path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
        },
        also_copy => { 't/lib' => 'source/t/lib' },
    },
);

{
    my $wd = File::pushd::pushd($tzil->root);
    cmp_deeply(
        [ Dist::Zilla::App::Command::stale->stale_modules($tzil) ],
        [ ],
        'app finds no stale modules',
    );
    Dist::Zilla::Plugin::PromptIfStale::__clear_already_checked();
}

# munge @INC so it contains the source dir
unshift @INC, File::Spec->catdir($tzil->tempdir, qw(source t lib));

$tzil->chrome->logger->set_debug(1);

is(
    exception { $tzil->build },
    undef,
    'build was not aborted',
);

cmp_deeply(
    $tzil->log_messages,
    superbagof(
        '[PromptIfStale] Unindexed provided locally (at t/lib/Unindexed.pm); skipping version check',
        '[DZ] writing DZT-Sample in ' . $tzil->tempdir->subdir('build'),
    ),
    'module skipped, due to being local',
) or diag 'got: ', explain $tzil->log_messages;

is(scalar @prompts, 0, 'there were no prompts');

done_testing;
