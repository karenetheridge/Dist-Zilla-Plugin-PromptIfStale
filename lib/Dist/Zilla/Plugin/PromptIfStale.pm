use strict;
use warnings;
package Dist::Zilla::Plugin::PromptIfStale;
# ABSTRACT: Check at build/release time if modules are out of date
# vim: set ts=8 sw=4 tw=78 et :

use Moose;
with 'Dist::Zilla::Role::BeforeBuild',
    'Dist::Zilla::Role::AfterBuild',
    'Dist::Zilla::Role::BeforeRelease';

use Moose::Util::TypeConstraints;
use MooseX::Types::Moose qw(ArrayRef Bool Str);
use List::MoreUtils qw(uniq none);
use version;
use Path::Tiny;
use Cwd;
use HTTP::Tiny;
use Encode;
use JSON;
use Module::Path 'module_path';
use Module::Metadata;
use Module::CoreList;
use namespace::autoclean;

sub mvp_multivalue_args { qw(modules skip) }
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

has skip_core_modules => (
    is => 'ro', isa => Bool,
    default => 0,
);

has check_all_plugins => (
    is => 'ro', isa => Bool,
    default => 0,
);

has check_all_prereqs => (
    is => 'ro', isa => Bool,
    default => 0,
);

has skip => (
    isa => ArrayRef[Str],
    traits => [ 'Array' ],
    handles => { skip => 'elements' },
    lazy => 1,
    default => sub { [] },
);

has fatal => (
    is => 'ro', isa => Bool,
    default => 0,
);

has index_base_url => (
    is => 'ro', isa => Str,
);

around dump_config => sub
{
    my ($orig, $self) = @_;
    my $config = $self->$orig;

    $config->{'' . __PACKAGE__} = {
        (map { $_ => ($self->$_ || 0) } qw(phase check_all_plugins check_all_prereqs)),
        (map { $_ => [ $self->$_ ] } qw(modules skip)),
    };

    return $config;
};

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
    if ($self->phase eq 'release')
    {
        my @modules = $self->_modules_before_build;
        push @modules, $self->_modules_prereq
            if $self->check_all_prereqs;
        $self->_check_modules( uniq @modules ) if @modules;
    }
}

# a package-scoped singleton variable that tracks the module names that have
# already been checked for, so other instances of this plugin do not duplicate
# the check.
my %already_checked;
sub __clear_already_checked { %already_checked = () } # for testing

sub _check_modules
{
    my ($self, @modules) = @_;

    $self->log('checking for stale modules...');

    my (@bad_modules, @prompts, %module_to_filename);
    foreach my $module (sort @modules)
    {
        next if $module eq 'perl';
        next if $already_checked{$module};
        next if $self->skip_core_modules
            and Module::CoreList->first_release($module) # was/is in core
            and not Module::CoreList->removed_from($module);#not yet removed

        my $path = module_path($module);
        if (not $path)
        {
            $already_checked{$module}++;
            push @bad_modules, $module;
            push @prompts, $module . ' is not installed.';
            next;
        }

        # ignore modules in the dist currently being built
        my $relative_path = path($path)->relative(getcwd);
        $self->log_debug($module . ' provided locally (at ' . $relative_path
                . '); skipping version check'), next
            unless $relative_path =~ m/^\.\./;

        $module_to_filename{$module} = $path;
    }

    foreach my $module (sort keys %module_to_filename)
    {
        my $indexed_version = $self->_indexed_version($module, !!(keys %module_to_filename > 5));
        my $local_version = Module::Metadata->new_from_file($module_to_filename{$module})->version;

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

    my $continue;
    if (not $self->fatal)
    {
        $prompt .= 'Continue anyway?';
        $continue = $self->zilla->chrome->prompt_yn($prompt, { default => 0 });
    }

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
        my @skip = $self->skip;
        return [
            grep { my $module = $_; none { $module eq $_ } @skip }
            uniq
                $self->modules,
                $self->check_all_plugins
                    ? map { $_->meta->name } @{ $self->zilla->plugins }
                    : ()
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
        my @skip = $self->skip;
        [
            grep { my $module = $_; none { $module eq $_ } @skip }
            map { keys %$_ }
            grep { defined }
            map { @{$_}{qw(requires recommends suggests)} }
            grep { defined }
            values %$prereqs
        ];
    },
);

my $packages;
sub _indexed_version
{
    my ($self, $module, $combined) = @_;

    # we download 02packages if we have several modules to query at once, or
    # if we were given a different URL to use -- otherwise, we perform an API
    # hit for just this one module's data
    return $combined || $packages || $self->index_base_url
        ? $self->_indexed_version_via_02packages($module)
        : $self->_indexed_version_via_query($module);
}

# I bet this is available somewhere as a module?
sub _indexed_version_via_query
{
    my ($self, $module) = @_;

    die 'should not be here - get 02packages instead' if $self->index_base_url;

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

    my $base = $self->index_base_url || 'http://www.cpan.org';

    my $response = HTTP::Tiny->new->mirror($base . '/modules/' . $filename, $path);
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
from all phases (C<configure>, C<build>, C<runtime>, C<test> and C<develop>) ,
and the C<requires>, C<recommends> and C<suggests> types.

=item * C<skip>

The name of a module to exempt from checking. Can be provided more than once.

=item * C<skip_core_modules>

A boolean, defaulting to false. Exempt from checking all the modules
that are present in the perl core. This prevents the prompts
for modules that you can't update anyway, because they require newer perl.

=item * C<fatal>

A boolean, defaulting to false, indicating that missing prereqs will result in
an immediate abort of the build/release process, without prompting.

=item * C<index_base_url>

=for stopwords darkpan

When provided, uses this base URL to fetch F<02packages.details.txt.gz>
instead of the default C<http://www.cpan.org>.  Use this when your
distribution uses prerequisites found only in your darkpan-like server.

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
