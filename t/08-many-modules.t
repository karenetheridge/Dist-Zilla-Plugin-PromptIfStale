use strict;
use warnings FATAL => 'all';

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Fatal;
use Test::Deep;
use Path::Tiny;
use Moose::Util 'find_meta';

BEGIN {
    use Dist::Zilla::Plugin::PromptIfStale;
    $Dist::Zilla::Plugin::PromptIfStale::VERSION = 9999
        unless $Dist::Zilla::Plugin::PromptIfStale::VERSION;
}

my @checked_via_02packages;
{
    my $meta = find_meta('Dist::Zilla::Plugin::PromptIfStale');
    $meta->make_mutable;
    $meta->add_around_method_modifier(_indexed_version_via_query => sub {
        my $orig = shift;
        my $self = shift;
        my ($module) = @_;
        die 'should not be checking for ' . $module;
    });
    $meta->add_around_method_modifier(_indexed_version_via_02packages => sub {
        my $orig = shift;
        my $self = shift;
        my ($module) = @_;

        $self->_get_packages;   # force this to be initialized in the class
        push(@checked_via_02packages, $module), return undef if $module =~ /^Unindexed[0-5]$/;
        die 'should not be checking for ' . $module;
    });
    my $packages;
}
{
    use Parse::CPAN::Packages::Fast;
    my $meta = find_meta('Parse::CPAN::Packages::Fast')
        || Class::MOP::Class->initialize('Parse::CPAN::Packages::Fast');
    my $initialized;
    $meta->add_around_method_modifier(new => sub {
        die if $initialized;
        'fake packages object ' . $initialized++;
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
    @INC{ ( map { 'Unindexed' . $_ . '.pm' } (0..5) ) } =
       ( qw(/tmp/bogusfile) x 6 );    # cannot be in our local dir or we will abort
}

my $tzil = Builder->from_config(
    { dist_root => 't/does-not-exist' },
    {
        add_files => {
            'source/dist.ini' => simple_ini(
                [ GatherDir => ],
                [ 'PromptIfStale' => { modules => [ map { 'Unindexed' . $_ } 0..5 ], phase => 'build' } ],
            ),
            path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
        },
    },
);

# no need to test all combinations - we sort the module list
my $full_prompt = "Issues found:\n"
    . join("\n", map { '    Unindexed' . $_ . ' is not indexed.' } 0..5)
    . "\nContinue anyway?";
$tzil->chrome->set_response_for($full_prompt, 'n');

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
    \@checked_via_02packages,
    [ map { 'Unindexed' . $_ } 0..5 ],
    'all modules checked using 02packages',
);

cmp_deeply(
    $tzil->log_messages,
    supersetof("[PromptIfStale] Aborting build\n[PromptIfStale] To remedy, do: cpanm " . join(' ', map { 'Unindexed' . $_ } (0..5))),
    'build was aborted, with remedy instructions',
) or diag 'got: ', explain $tzil->log_messages;

done_testing;
