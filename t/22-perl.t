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

use lib 't/lib';
use NoNetworkHits;

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

{
    my $meta = find_meta('Dist::Zilla::Plugin::PromptIfStale');
    $meta->make_mutable;
    $meta->add_around_method_modifier(_indexed_version => sub {
        my $orig = shift;
        my $self = shift;
        my ($module) = @_;

        return version->parse('200.0') if $module eq 'strict' or $module eq 'Carp';
        die 'should not be checking for ' . $module;
    });
    $meta->add_around_method_modifier(_is_duallifed => sub {
        my $orig = shift;
        my $self = shift;
        my ($module) = @_;

        return if $module eq 'strict';
        return 1 if $module eq 'Carp';
        die 'should not be checking for ' . $module;
    });
}

{
    my $tzil = Builder->from_config(
        { dist_root => 't/does-not-exist' },
        {
            add_files => {
                path(qw(source dist.ini)) => simple_ini(
                    [ GatherDir => ],
                    [ 'PromptIfStale' => { modules => [ 'strict' ], phase => 'build' } ],
                ),
                path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
            },
        },
    );

    $tzil->chrome->logger->set_debug(1);

    {
        my $wd = pushd $tzil->root;
        cmp_deeply(
            [ Dist::Zilla::App::Command::stale->stale_modules($tzil) ],
            [ ],
            'app finds no stale modules',
        );
        Dist::Zilla::Plugin::PromptIfStale::__clear_already_checked();
    }

    is(
        exception { $tzil->build },
        undef,
        'build succeeded when the stale module is core only',
    );

    is(scalar @prompts, 0, 'there were no prompts') or diag 'got: ', explain \@prompts;

    cmp_deeply(
        $tzil->log_messages,
        superbagof(
            '[PromptIfStale] comparing indexed vs. local version for strict: indexed=200.0; local version=' . strict->VERSION,
            re(qr/^\Q[DZ] writing DZT-Sample in /),
        ),
        'build completed successfully',
    ) or diag 'saw log messages: ', explain $tzil->log_messages;
}

@prompts = ();
{
    my $tzil = Builder->from_config(
        { dist_root => 't/does-not-exist' },
        {
            add_files => {
                path(qw(source dist.ini)) => simple_ini(
                    [ GatherDir => ],
                    [ 'PromptIfStale' => { modules => [ 'Carp' ], phase => 'build' } ],
                ),
                path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
            },
        },
    );

    my $prompt = 'Carp is indexed at version 200.0 but you only have ' . Carp->VERSION
        . ' installed. Continue anyway?';
    $tzil->chrome->set_response_for($prompt, 'y');

    $tzil->chrome->logger->set_debug(1);

    {
        my $wd = pushd $tzil->root;
        cmp_deeply(
            [ Dist::Zilla::App::Command::stale->stale_modules($tzil) ],
            [ 'Carp' ],
            'app finds stale modules',
        );
        Dist::Zilla::Plugin::PromptIfStale::__clear_already_checked();
    }

    is(
        exception { $tzil->build },
        undef,
        'build proceeds normally',
    );

    cmp_deeply(
        \@prompts,
        [ $prompt ],
        'we were indeed prompted',
    );

    cmp_deeply(
        $tzil->log_messages,
        superbagof(
            '[PromptIfStale] comparing indexed vs. local version for Carp: indexed=200.0; local version=' . Carp->VERSION,
            re(qr/^\Q[DZ] writing DZT-Sample in /),
        ),
        'build completed successfully',
    ) or diag 'saw log messages: ', explain $tzil->log_messages;
}

done_testing;
