use strict;
use warnings FATAL => 'all';

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Fatal;
use Test::Deep;
use Path::Tiny;
use File::pushd 'pushd';
use Moose::Util 'find_meta';
use Dist::Zilla::App::Command::stale;

use lib 't/lib';
use NoNetworkHits;
use EnsureStdinTty;

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
    use Dist::Zilla::Plugin::PromptIfStale;
    my $meta = find_meta('Dist::Zilla::Plugin::PromptIfStale');
    $meta->make_mutable;
    $meta->add_around_method_modifier(_indexed_version => sub {
        my $orig = shift;
        my $self = shift;
        my ($module) = @_;
        return version->parse('200.0') if $module eq 'Carp';
        return version->parse('100.0') if $module eq 'Dist::Zilla::Plugin::GatherDir';
        die 'should not be checking for ' . $module;
    });
    $meta->add_around_method_modifier(_is_duallifed => sub {
        my $orig = shift;
        my $self = shift;
        my ($module) = @_;

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
                    [ 'PromptIfStale' => {
                            check_authordeps => 1,
                            phase => 'build',
                            skip => [qw(Dist::Zilla::Plugin::PromptIfStale)],
                        },
                    ],
                ) . "\n\n; authordep I::Am::Not::Installed\n; authordep Carp\n",
                path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
            },
        },
    );

    $tzil->chrome->logger->set_debug(1);

    {
        my $wd = pushd $tzil->root;
        cmp_deeply(
            [ Dist::Zilla::App::Command::stale->stale_modules($tzil) ],
            bag(qw(Dist::Zilla::Plugin::GatherDir I::Am::Not::Installed Carp)),
            'app finds uninstalled and stale authordeps',
        );
        Dist::Zilla::Plugin::PromptIfStale::__clear_already_checked();
    }

    my $prompt = '3 stale modules found, continue anyway?';
    $tzil->chrome->set_response_for($prompt, 'n');

    like(
        exception { $tzil->build },
        qr/\Q[PromptIfStale] Aborting build\E/,
        'build aborted',
    );

    cmp_deeply(
        \@prompts,
        [ $prompt ],
        'we were indeed prompted',
    );

    cmp_deeply(
        $tzil->log_messages,
        superbagof("[PromptIfStale] Aborting build due to stale modules!"),
        'build was aborted, with remedy instructions',
    ) or diag 'saw log messages: ', explain $tzil->log_messages;
}

@prompts = ();
Dist::Zilla::Plugin::PromptIfStale::__clear_already_checked();

{
    my $tzil = Builder->from_config(
        { dist_root => 't/does-not-exist' },
        {
            add_files => {
                path(qw(source dist.ini)) => simple_ini(
                    [ GatherDir => ],
                    [ 'PromptIfStale' => { phase => 'build' },
                    ],
                ) . "\n\n; authordep I::Am::Not::Installed\n",
                path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
            },
        },
    );

    {
        my $wd = pushd $tzil->root;
        cmp_deeply(
            [ Dist::Zilla::App::Command::stale->stale_modules($tzil) ],
            [ ],
            'app does not check authordeps without --all',
        );
        Dist::Zilla::Plugin::PromptIfStale::__clear_already_checked();
    }

    $tzil->chrome->logger->set_debug(1);

    is(
        exception { $tzil->build },
        undef,
        'build succeeded - nothing checked',
    );

    cmp_deeply(
        \@prompts,
        [ ],
        'there were no prompts',
    );

    diag 'got prompts: ', explain $tzil->log_messages
        if not Test::Builder->new->is_passing;
}

done_testing;
