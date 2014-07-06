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
use version;

BEGIN {
    use Dist::Zilla::Plugin::PromptIfStale;
    $Dist::Zilla::Plugin::PromptIfStale::VERSION = 9999
        unless $Dist::Zilla::Plugin::PromptIfStale::VERSION;

    use Dist::Zilla::App::Command::stale;
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

SKIP: {
    # Note that this test uses the network to query the index for our own module.
    skip('this test can always be expected to work only for the author', 1)
        unless $ENV{AUTHOR_TESTING};

    my $tzil = Builder->from_config(
        { dist_root => 't/does-not-exist' },
        {
            add_files => {
                path(qw(source dist.ini)) => simple_ini(
                    [ GatherDir => ],
                    [ 'PromptIfStale' => { modules => [ 'Dist::Zilla::Plugin::PromptIfStale' ], phase => 'build' } ],
                ),
                path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
            },
        },
    );

    {
        my $wd = pushd $tzil->root;
        cmp_deeply(
            [ Dist::Zilla::App::Command::stale->stale_modules($tzil) ],
            [],
            'no stale modules found',
        );
        Dist::Zilla::Plugin::PromptIfStale::__clear_already_checked();
    }

    # if a response has not been configured for a particular prompt, we will die
    is(
        exception { $tzil->build },
        undef,
        'build succeeded when checking for a module that is not stale',
    );

    is(scalar @prompts, 0, 'there were no prompts') or diag 'got: ', explain \@prompts;
}


# now let's craft a situation where we know our module is stale, and confirm
# we prompt properly about it.
# This also saves us from having to do a real HTTP hit.

# ensure we find the helper module, before we change directories
unshift @INC, path(qw(t lib))->absolute->stringify;
require NoNetworkHits;

{
    my $meta = find_meta('Dist::Zilla::Plugin::PromptIfStale');
    $meta->make_mutable;
    $meta->add_around_method_modifier(_indexed_version => sub {
        my $orig = shift;
        my $self = shift;
        my ($module) = @_;

        return version->parse('200.0') if $module eq 'StaleModule';
        die 'should not be checking for ' . $module;
    });
}

@prompts = ();

my $tzil = Builder->from_config(
    { dist_root => 't/does-not-exist' },
    {
        add_files => {
            path(qw(source dist.ini)) => simple_ini(
                [ GatherDir => ],
                [ 'PromptIfStale' => { modules => [ 'StaleModule' ], phase => 'build' } ],
            ),
            path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
        },
        also_copy => { 't/lib' => 't/lib' },
    },
);

my $prompt = 'StaleModule is indexed at version 200.0 but you only have 1.0 installed. Continue anyway?';
$tzil->chrome->set_response_for($prompt, 'y');

$tzil->chrome->logger->set_debug(1);

# ensure we find the library, not in a local directory, before we change directories
unshift @INC, path($tzil->tempdir, qw(t lib))->stringify;

{
    my $wd = pushd $tzil->root;
    cmp_deeply(
        [ Dist::Zilla::App::Command::stale->stale_modules($tzil) ],
        [ 'StaleModule' ],
        'app finds stale modules',
    );
    Dist::Zilla::Plugin::PromptIfStale::__clear_already_checked();
}

is(
    exception { $tzil->build },
    undef,
    'build proceeds normally',
);

cmp_deeply(\@prompts, [ $prompt ], 'we were indeed prompted');

my $build_dir = path($tzil->tempdir)->child('build');

cmp_deeply(
    $tzil->log_messages,
    superbagof(
        '[PromptIfStale] comparing indexed vs. local version for StaleModule: indexed=200.0; local version=1.0',
        re(qr/^\Q[DZ] writing DZT-Sample in /),
    ),
    'build completed successfully',
) or diag 'saw log messages: ', explain $tzil->log_messages;

done_testing;
