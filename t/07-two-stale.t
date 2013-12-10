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
use version;

use lib 't/lib';
use NoNetworkHits;

BEGIN {
    use Dist::Zilla::Plugin::PromptIfStale;
    $Dist::Zilla::Plugin::PromptIfStale::VERSION = 9999
        unless $Dist::Zilla::Plugin::PromptIfStale::VERSION;
}

{
    my $meta = find_meta('Dist::Zilla::Plugin::PromptIfStale');
    $meta->make_mutable;
    $meta->add_around_method_modifier(_indexed_version => sub {
        my $orig = shift;
        my $self = shift;
        my ($module) = @_;

        return version->parse('200.0') if $module eq 'Indexed::But::Not::Installed';
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
                [ 'PromptIfStale' => { modules => [ 'Indexed::But::Not::Installed', 'Unindexed' ], phase => 'build' } ],
            ),
            path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
        },
        also_copy => { 't/lib' => 't/lib' },
    },
);

# no need to test all combinations - we sort the module list

my $full_prompt = "Issues found:
    Indexed::But::Not::Installed is not installed.
    Unindexed is not indexed.
Continue anyway?";
$tzil->chrome->set_response_for($full_prompt, 'n');

$tzil->chrome->logger->set_debug(1);

unshift @INC, File::Spec->catdir($tzil->tempdir, qw(t lib));

like(
    exception { $tzil->build },
    qr/\Q[PromptIfStale] Aborting build\E/,
    'build aborted',
);

cmp_deeply(
    \@prompts,
    [ $full_prompt ],
    'we were indeed prompted',
);

cmp_deeply(
    $tzil->log_messages,
    superbagof("[PromptIfStale] Aborting build\n[PromptIfStale] To remedy, do: cpanm Indexed::But::Not::Installed Unindexed"),
    'build was aborted, with remedy instructions',
) or diag 'got: ', explain $tzil->log_messages;

done_testing;
