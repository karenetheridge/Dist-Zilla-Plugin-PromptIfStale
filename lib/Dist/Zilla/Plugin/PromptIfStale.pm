use strict;
use warnings;
package Dist::Zilla::Plugin::PromptIfStale;
# ABSTRACT: Check at build/release time if modules are out of date

use Moose;
with 'Dist::Zilla::Role::BeforeBuild',
    'Dist::Zilla::Role::AfterBuild',
    'Dist::Zilla::Role::BeforeRelease';

use Moose::Util::TypeConstraints;
use MooseX::Types::Moose qw(ArrayRef Bool Str);
use List::MoreUtils 'uniq';
use Module::Runtime qw(module_notional_filename use_module);
use version;
use Path::Tiny;
use Cwd;
use HTTP::Tiny;
use Encode;
use JSON;
use namespace::autoclean;

sub mvp_multivalue_args { 'modules' }
sub mvp_aliases { {
    module => 'modules',
    check_all => 'check_all_plugins',
} }

has phase => (
    is => 'ro',
    isa => enum([qw(build release)]),
    default => 'release',
);

has modules => (
    isa => ArrayRef[Str],
    traits => [ 'Array' ],
    handles => { modules => 'elements' },
    lazy => 1,
    default => sub { [] },
);

has check_all_plugins => (
    is => 'ro', isa => Bool,
    default => 0,
);

has check_all_prereqs => (
    is => 'ro', isa => Bool,
    default => 0,
);

sub before_build
{
    my $self = shift;

    if ($self->phase eq 'build')
    {
        my @modules = $self->_modules_before_build;
        $self->_check_modules(@modules) if @modules;
    }
}

sub after_build
{
    my $self = shift;

    if ($self->phase eq 'build' and $self->check_all_prereqs)
    {
        my @modules = $self->_modules_prereq;
        $self->_check_modules(@modules) if @modules;
    }
}

sub before_release
{
    my $self = shift;

    $self->_check_modules(
        uniq $self->_modules_before_build, $self->_modules_prereq
    ) if $self->phase eq 'release';
}

# a package-scoped singleton variable that tracks the module names that have
# already been checked for, so other instances of this plugin do not duplicate
# the check.
my %already_checked;

sub _check_modules
{
    my ($self, @modules) = @_;

    $self->log('checking for stale modules...');

    my (@bad_modules, @prompts);
    foreach my $module (sort { $a cmp $b } @modules)
    {
        next if $module eq 'perl';
        next if $already_checked{$module};

        if (not eval { use_module($module); 1 })
        {
            $already_checked{$module}++;
            push @bad_modules, $module;
            push @prompts, $module . ' is not installed.';
            next;
        }

        # ignore modules in the dist currently being built
        $self->log_debug($module . ' provided locally; skipping version check'), next
            unless path($INC{module_notional_filename($module)})->relative(getcwd) =~ m/^\.\./;

        my $indexed_version = $self->_indexed_version($module, !!(@modules > 5));
        my $local_version = version->parse($module->VERSION) || 0;

        $self->log_debug('comparing indexed vs. local version for ' . $module
            . ': indexed=' . ($indexed_version // 'undef')
            . '; local version=' . ($local_version // 'undef'));

        if (not defined $indexed_version)
        {
            $already_checked{$module}++;
            push @bad_modules, $module;
            push @prompts, $module . ' is not indexed.';
            next;
        }

        if (defined $local_version
            and $local_version < $indexed_version)
        {
            $already_checked{$module}++;
            push @bad_modules, $module;
            push @prompts, 'Indexed version of ' . $module . ' is ' . $indexed_version
                    . ' but you only have ' . $local_version
                    . ' installed.';
            next;
        }
    }

    return if not @prompts;

    my $prompt = @prompts > 1
        ? (join("\n    ", 'Issues found:', @prompts) . "\n")
        : ($prompts[0] . ' ');
    $prompt .= 'Continue anyway?';

    my $continue = $self->zilla->chrome->prompt_yn($prompt, { default => 0 });
    $self->log_fatal('Aborting ' . $self->phase . "\n"
        . 'To remedy, do: cpanm ' . join(' ', @bad_modules)) if not $continue;
}

has _modules_before_build => (
    isa => 'ArrayRef[Str]',
    traits => ['Array'],
    handles => { _modules_before_build => 'elements' },
    lazy => 1,
    default => sub {
        my $self = shift;
        return [ uniq
            $self->modules,
            $self->check_all_plugins
                ? map { blessed $_ } @{ $self->zilla->plugins }
                : (),
        ];
    },
);

has _modules_prereq => (
    isa => 'ArrayRef[Str]',
    traits => ['Array'],
    handles => { _modules_prereq => 'elements' },
    lazy => 1,
    default => sub {
        my $self = shift;
        my $prereqs = $self->zilla->prereqs->as_string_hash;
        [
            map { keys %$_ }
            grep { defined }
            map { @{$_}{qw(requires recommends suggests)} }
            grep { defined }
            @{$prereqs}{qw(configure build runtime test develop)}
        ];
    },
);

my $packages;
sub _indexed_version
{
    my ($self, $module, $combined) = @_;

    return $combined || $packages
        ? $self->_indexed_version_via_02packages($module)
        : $self->_indexed_version_via_query($module);
}

# I bet this is available somewhere as a module?
sub _indexed_version_via_query
{
    my ($self, $module) = @_;

    my $res = HTTP::Tiny->new->get("http://cpanidx.org/cpanidx/json/mod/$module");
    $self->log_debug('could not query the index?'), return undef if not $res->{success};

    # JSON wants UTF-8 bytestreams, so we need to re-encode no matter what
    # encoding we got. -- rjbs, 2011-08-18 (in Dist::Zilla)
    my $json_octets = Encode::encode_utf8($res->{content});
    my $payload = JSON::->new->decode($json_octets);

    $self->log_debug('invalid payload returned?'), return undef unless $payload;
    $self->log_debug($module . ' not indexed'), return undef if not defined $payload->[0]{mod_vers};
    version->parse($payload->[0]{mod_vers});
}

# TODO: it would be AWESOME to provide this to multiple plugins via a role
# even better would be to save the file somewhere semi-permanent and
# keep it refreshed with a Last-Modified header - or share cpanm's copy?
sub _get_packages
{
    my $self = shift;
    return $packages if $packages;

    require File::Temp;
    my $tempdir = File::Temp::tempdir(CLEANUP => 1);
    my $filename = '02packages.details.txt.gz';
    my $path = path($tempdir, $filename);

    my $response = HTTP::Tiny->new->mirror('http://www.cpan.org/modules/' . $filename, $path);
    $self->log_debug('could not fetch the index?'), return undef if not $response->{success};

    require Parse::CPAN::Packages::Fast;
    $packages = Parse::CPAN::Packages::Fast->new($path->stringify);
}

sub _indexed_version_via_02packages
{
    my ($self, $module) = @_;

    my $package = $self->_get_packages->package($module);
    return undef if not $package;
    version->parse($package->version);
}

__PACKAGE__->meta->make_immutable;
__END__

=pod

=head1 SYNOPSIS

In your F<dist.ini>:

    [PromptIfStale]
    phase = build
    module = Dist::Zilla
    module = Dist::Zilla::PluginBundle::Author::ME

or:

    [PromptIfStale]
    check_all_plugins = 1

=head1 DESCRIPTION

C<[PromptIfStale]> is a C<BeforeBuild> or C<BeforeRelease> plugin that compares the
locally-installed version of a module(s) with the latest indexed version,
prompting to abort the build process if a discrepancy is found.

Note that there is no effect on the built dist -- all actions are taken at
build time.

=head1 OPTIONS

=over 4

=item * C<phase>

Indicates whether the checks are performed at I<build> or I<release> time
(defaults to I<release>).

(Remember that you can use different settings for different phases by employing
this plugin twice, with different names.)

=item * C<module>

The name of a module to check for. Can be provided more than once.

=item * C<check_all_plugins>

A boolean, defaulting to false, indicating that all plugins being used to
build this distribution should be checked.

=item * C<check_all_prereqs>

A boolean, defaulting to false, indicating that all prerequisites in the
distribution metadata should be checked. The modules are a merged list taken
from the C<configure>, C<build>, C<runtime>, C<test> and C<develop> phases,
and the C<requires>, C<recommends> and C<suggests> types.

=back

=for Pod::Coverage mvp_multivalue_args mvp_aliases before_build after_build before_release

=head1 SUPPORT

=for stopwords irc

Bugs may be submitted through L<the RT bug tracker|https://rt.cpan.org/Public/Dist/Display.html?Name=Dist-Zilla-Plugin-PromptIfStale>
(or L<bug-Dist-Zilla-Plugin-PromptIfStale@rt.cpan.org|mailto:bug-Dist-Zilla-Plugin-PromptIfStale@rt.cpan.org>).
I am also usually active on irc, as 'ether' at C<irc.perl.org>.

=head1 SEE ALSO

=begin :list

* L<Dist::Zilla::Plugin::Prereqs::MatchInstalled>, L<Dist::Zilla::Plugin::Prereqs::MatchInstalled::All>

=end :list

=cut
