use strict;
use warnings FATAL => 'all';

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Deep;
use Path::Tiny;
use Moose::Util 'find_meta';
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

my $checked_app;
BUILD:
my $tzil = Builder->from_config(
    { dist_root => 't/does-not-exist' },
    {
        add_files => {
            path(qw(source dist.ini)) => simple_ini(
                [ GatherDir => ],
                do {
                    my $mod = '0';
                    map {
                        my $phase = $_;
                        map {
                            [ 'Prereqs' => $phase . $_ => { 'Foo' . $mod++ => 0 } ]
                        } qw(Requires Recommends Suggests)
                    } qw(Runtime Test Develop);
                },
                [ 'PromptIfStale' => {
                        check_all_prereqs => 1,
                        # some of these are duplicated with prereqs
                        module => [ 'Bar', map { 'Foo' . $_ } 0 .. 2 ], phase => 'build'
                    },
                ],
            ),
            path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
        },
    },
);

if (not $checked_app++)
{
    my $wd = File::pushd::pushd($tzil->root);
    cmp_deeply(
        [ Dist::Zilla::App::Command::stale->stale_modules($tzil) ],
        [ 'Bar', map { 'Foo' . $_ } ('0' .. '8') ],
        'app finds stale modules',
    );
    Dist::Zilla::Plugin::PromptIfStale::__clear_already_checked();
    goto BUILD;
}


my %expected_prompts = (
    before_build => [
        map { '    ' . $_ . ' is not installed.' } 'Bar', map { 'Foo' . $_ } ('0' .. '2') ],
    after_build => [
        map { '    ' . $_ . ' is not installed.' } map { 'Foo' . $_ } ('3' .. '8') ],
);

my @expected_prompts = map {
    "Issues found:\n" . join("\n", @{$expected_prompts{$_}}, 'Continue anyway?')
} qw(before_build after_build);

$tzil->chrome->set_response_for($_, 'y') foreach @expected_prompts;

$tzil->build;

cmp_deeply(
    \@prompts,
    \@expected_prompts,
    'we were indeed prompted, for exactly all the right phases and types, and not twice for the duplicates',
);

done_testing;
