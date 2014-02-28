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
    skip('this test can always be expected to work only for the author', 1)
        unless $ENV{AUTHOR_TESTING};

    my $tzil = Builder->from_config(
        { dist_root => 't/does-not-exist' },
        {
            add_files => {
                'source/dist.ini' => simple_ini(
                    [ GatherDir => ],
                    [ 'PromptIfStale' => { modules => [ 'Dist::Zilla::Plugin::PromptIfStale' ], phase => 'build' } ],
                ),
                path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
            },
        },
    );

    {
        my $wd = File::pushd::pushd($tzil->root);
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

unshift @INC, File::Spec->catdir(qw(t lib));
require NoNetworkHits;

{
    my $meta = find_meta('Dist::Zilla::Plugin::PromptIfStale');
    $meta->make_mutable;
    $meta->add_around_method_modifier(_indexed_version => sub {
        my $orig = shift;
        my $self = shift;
        my ($module) = @_;

        return version->parse('200.0') if $module eq 'strict';
        die 'should not be checking for ' . $module;
    });
}

@prompts = ();

my $tzil = Builder->from_config(
    { dist_root => 't/does-not-exist' },
    {
        add_files => {
            'source/dist.ini' => simple_ini(
                [ GatherDir => ],
                [ 'PromptIfStale' => { modules => [ 'strict' ], phase => 'build' } ],
            ),
            path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
        },
    },
);

{
    my $wd = File::pushd::pushd($tzil->root);
    cmp_deeply(
        [ Dist::Zilla::App::Command::stale->stale_modules($tzil) ],
        [ 'strict' ],
        'app finds stale modules',
    );
    Dist::Zilla::Plugin::PromptIfStale::__clear_already_checked();
}

my $prompt = 'Indexed version of strict is 200.0 but you only have ' . strict->VERSION
    . ' installed. Continue anyway?';
$tzil->chrome->set_response_for($prompt, 'y');

$tzil->chrome->logger->set_debug(1);

$tzil->build;

cmp_deeply(\@prompts, [ $prompt ], 'we were indeed prompted');

my $build_dir = path($tzil->tempdir)->child('build');

cmp_deeply(
    $tzil->log_messages,
    superbagof(
        '[PromptIfStale] comparing indexed vs. local version for strict: indexed=200.0; local version=' . strict->VERSION,
        re(qr/^\Q[DZ] writing DZT-Sample in /),
    ),
    'build completed successfully',
) or diag 'got: ', explain $tzil->log_messages;

done_testing;
