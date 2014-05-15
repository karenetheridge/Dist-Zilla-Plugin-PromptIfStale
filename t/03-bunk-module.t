use strict;
use warnings FATAL => 'all';

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Fatal;
use File::Spec;
use Path::Tiny;
use Test::Deep;
use Moose::Util 'find_meta';
use File::pushd 'pushd';
use Dist::Zilla::App::Command::stale;

use lib 't/lib';
use NoNetworkHits;

# simulate a response from the PAUSE index, without having to do a real HTTP hit
{
    use Dist::Zilla::Plugin::PromptIfStale;
    my $meta = find_meta('Dist::Zilla::Plugin::PromptIfStale');
    $meta->make_mutable;
    $meta->add_around_method_modifier(_indexed_version => sub {
        my $orig = shift;
        my $self = shift;
        my ($module) = @_;

        return undef if $module eq 'Unindexed';
        die 'should not be checking for ' . $module;
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
            path(qw(source dist.ini)) => simple_ini(
                [ GatherDir => ],
                [ 'PromptIfStale' => { modules => [ 'Unindexed' ], phase => 'build' } ],
            ),
            path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
        },
        also_copy => { 't/lib' => 't/lib' },
    },
);

my $prompt = 'Unindexed is not indexed. Continue anyway?';
$tzil->chrome->set_response_for($prompt, 'n');

$tzil->chrome->logger->set_debug(1);

unshift @INC, File::Spec->catdir($tzil->tempdir, qw(t lib));

{
    my $wd = pushd $tzil->root;
    cmp_deeply(
        [ Dist::Zilla::App::Command::stale->stale_modules($tzil) ],
        [ 'Unindexed' ],
        'app finds stale modules',
    );
    Dist::Zilla::Plugin::PromptIfStale::__clear_already_checked();
}


like(
    exception { $tzil->build },
    qr/^\Q[PromptIfStale] Aborting build\E/,
    'build aborted',
);

cmp_deeply(
    \@prompts,
    [ $prompt ],
    'we were indeed prompted',
);

cmp_deeply(
    $tzil->log_messages,
    superbagof(
       '[PromptIfStale] comparing indexed vs. local version for Unindexed: indexed=undef; local version=2.0',
        "[PromptIfStale] Aborting build\n[PromptIfStale] To remedy, do: cpanm Unindexed",
    ),
    'build was aborted, with remedy instructions',
) or diag 'saw log messages: ', explain $tzil->log_messages;

done_testing;
