use strict;
use warnings FATAL => 'all';

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Fatal;
use Test::Deep;
use Path::Tiny;
use Moose::Util 'find_meta';

SKIP: {
    skip('this test can always be expected to work only for the author', 1)
        unless $ENV{AUTHOR_TESTING};

    skip('this test can only be run from a dzil build dir (plugin needs a version)', 1)
        if -d '.git';

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

    # if a response has not been configured for a particular prompt, we will die
    is(
        exception { $tzil->build },
        undef,
        'no prompts when checking for a module that is not stale',
    );
}


# now let's craft a situation where we know our module is stale, and confirm
# we prompt properly about it.
# This also saves us from having to do a real HTTP hit.

use Dist::Zilla::Plugin::PromptIfStale; # make sure we are loaded!!

{
    my $meta = find_meta('Dist::Zilla::Plugin::PromptIfStale');
    $meta->make_mutable;
    $meta->add_around_method_modifier(_indexed_version => sub {
        my $orig = shift;
        my $self = shift;
        my ($module) = @_;

        return version->parse('200.0') if $module eq 'strict';
        die 'should not be checking for ' . $module;
        return $self->$orig(@_);
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
                [ 'PromptIfStale' => { modules => [ 'strict' ], phase => 'build' } ],
            ),
            path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
        },
    },
);

my $prompt = 'Indexed version of strict is 200.0 but you only have ' . strict->VERSION
    . ' installed. Continue anyway?';
$tzil->chrome->set_response_for($prompt, 'y');

$tzil->chrome->logger->set_debug(1);

$tzil->build;

cmp_deeply(\@prompts, [ $prompt ], 'we were indeed prompted');

my $build_dir = $tzil->tempdir->subdir('build');

cmp_deeply(
    $tzil->log_messages,
    supersetof(
        '[PromptIfStale] comparing indexed vs. local version for strict: indexed=200.0; local version=' . strict->VERSION,
        '[DZ] writing DZT-Sample in ' . $build_dir,
    ),
    'build completed successfully',
);


done_testing;
