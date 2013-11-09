use strict;
use warnings FATAL => 'all';

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Deep;
use Path::Tiny;
use Moose::Util 'find_meta';
use List::Util 'first';

for my $case ( 0, 1 ) {

    subtest "check_all_prereqs => $case" => sub {

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
                                phase => 'release',
                                check_all_prereqs => $case,
                                # some of these are duplicated with prereqs
                                module => [ 'Bar', map { 'Foo' . $_ } 0 .. 2 ]
                            },
                        ],
                        [ 'FakeRelease' ],
                    ),
                    path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
                },
            },
        );

        # if check_all_prereqs is true, then we should see errors on Foo 0 to 8, otherwise, just
        # specifically requested 0 to 2

        my $last = $case ? '8' : '2';
        my %expected_prompts = (
            before_release => [
                map { '    ' . $_ . ' is not installed.' } 'Bar', map { 'Foo' . $_ } ('0' .. $last) ],
        );

        my @expected_prompts = map {
            "Issues found:\n" . join("\n", @{$expected_prompts{$_}}, 'Continue anyway?')
        } qw(before_release);

        $tzil->chrome->set_response_for($_, 'y') foreach @expected_prompts;

        eval { $tzil->release }; # because aborting is log_fatal

        cmp_deeply(
            \@prompts,
            \@expected_prompts,
            'we were indeed prompted, for exactly all the right phases and types, and not twice for the duplicates',
        );

        Dist::Zilla::Plugin::PromptIfStale::__clear_already_checked();
    }
}

done_testing;
