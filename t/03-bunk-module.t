use strict;
use warnings FATAL => 'all';

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Fatal;
use Path::Tiny;
use Test::Deep;
use Moose::Util 'find_meta';

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

{
    package Unindexed;
    our $VERSION = '2.0';
    $INC{'Unindexed.pm'} = '/tmp/bogusfile';    # cannot be in our local dir or we will abort
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
    },
);

my $prompt = 'Unindexed is not indexed. Continue anyway?';
$tzil->chrome->set_response_for($prompt, 'n');

$tzil->chrome->logger->set_debug(1);

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
    supersetof(
       '[PromptIfStale] comparing indexed vs. local version for Unindexed: indexed=undef; local version=2.0',
        "[PromptIfStale] Aborting build\n[PromptIfStale] To remedy, do: cpanm Unindexed",
    ),
    'build was aborted, with remedy instructions',
) or diag 'got: ', explain $tzil->log_messages;

done_testing;
