use strict;
use warnings FATAL => 'all';

use Test::More;
use Test::Warnings;
use Test::DZil;
use Test::Fatal;
use Test::Deep;
use Path::Tiny;
use Moose::Util 'find_meta';

# simulate a response from the PAUSE index, without having to do a real HTTP hit

use Dist::Zilla::Plugin::PromptIfStale; # make sure we are loaded!!

{
    my $meta = find_meta('Dist::Zilla::Plugin::PromptIfStale');
    $meta->make_mutable;
    $meta->add_around_method_modifier(_indexed_version => sub {
        my $orig = shift;
        my $self = shift;
        my ($module) = @_;

        return version->parse('200.0') if $module eq 'Indexed::But::Not::Installed';
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
                [ 'PromptIfStale' => { modules => [ 'Indexed::But::Not::Installed' ], phase => 'build' } ],
            ),
            path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
        },
    },
);

my $prompt = 'Indexed::But::Not::Installed is not installed. Continue anyway?';
$tzil->chrome->set_response_for($prompt, 'n');

like(
    exception { $tzil->build },
    qr/\Q[PromptIfStale] Aborting build\E/,
    'build aborted',
);

is($prompts[0], $prompt, 'we were indeed prompted');

cmp_deeply(
    $tzil->log_messages,
    supersetof('[PromptIfStale] Aborting build'),
    'build was aborted',
);

done_testing;
