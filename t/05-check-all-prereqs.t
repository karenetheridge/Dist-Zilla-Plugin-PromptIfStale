use strict;
use warnings FATAL => 'all';

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Deep;
use Path::Tiny;
use Moose::Util 'find_meta';
use List::Util 'first';

use Dist::Zilla::Plugin::PromptIfStale; # make sure we are loaded!!

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

my @expected_prompts = (
    map { $_ . ' is not installed. Continue anyway?' } 'Bar', map { 'Foo' . $_ } ('0' .. '8'),
);
$tzil->chrome->set_response_for($_, 'y') foreach @expected_prompts;

$tzil->build;

cmp_deeply(
    \@prompts,
    bag(@expected_prompts),
    'we were indeed prompted, for exactly all the right phases and types, and not twice for the duplicates',
);

done_testing;
