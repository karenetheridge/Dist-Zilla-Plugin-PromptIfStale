use strict;
use warnings;
package Dist::Zilla::Plugin::PromptIfStale;
# ABSTRACT: Check at build time if modules are out of date

use Moose;
with 'Dist::Zilla::Role::BeforeBuild',
    'Dist::Zilla::Role::BeforeRelease';

use Moose::Util::TypeConstraints;
use MooseX::Types::Moose qw(ArrayRef Bool);
use MooseX::Types::LoadableClass 'LoadableClass';
use List::MoreUtils 'uniq';
use Module::Runtime 'use_module';
use version;
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
    isa => ArrayRef[LoadableClass],
    traits => [ 'Array' ],
    handles => { modules => 'elements' },
    lazy => 1,
    default => sub { [] },
);

has check_all_plugins => (
    is => 'ro', isa => Bool,
    default => 0,
);

sub before_build
{
    my $self = shift;
    $self->check_modules if $self->phase eq 'build';
}

sub before_release
{
    my $self = shift;
    $self->check_modules if $self->phase eq 'release';
}

sub check_modules
{
    my $self = shift;

    my @modules = $self->check_all_plugins
        ? uniq map { blessed $_ } @{ $self->zilla->plugins }
        : $self->modules;

    foreach my $module (@modules)
    {
        my $indexed_version = $self->_indexed_version($module);
        my $local_version = version->parse(use_module($module)->VERSION);

        $self->log_debug('comparing indexed vs. local version for ' . $module);

        if (defined $indexed_version
            and defined $local_version
            and $local_version < $indexed_version)
        {
            my $abort = $self->zilla->chrome->prompt_yn(
                'Indexed version of ' . $module . ' is ' . $indexed_version
                    . ' but you only have ' . $local_version
                    . ' installed. Abort the build?',
                { default => 1 },
            );

            $self->log_fatal('Aborting build') if $abort;
        }
    }
}

# I bet this is available somewhere as a module?
sub _indexed_version
{
    my ($self, $module) = @_;

    my $res = HTTP::Tiny->new->get("http://cpanidx.org/cpanidx/json/mod/$module");
    $self->log_debug('could not query the index?'), return undef if not $res->{success};

    # JSON wants UTF-8 bytestreams, so we need to re-encode no matter what
    # encoding we got. -- rjbs, 2011-08-18 (in Dist::Zilla)
    my $json_octets = Encode::encode_utf8($res->{content});
    my $payload = JSON::->new->decode($json_octets);

    $self->log_debug('invalid payload returned?'), return undef unless \@$payload;
    $self->log_debug($module . ' not indexed'), return undef if not defined $payload->[0]{mod_vers};
    version->parse($payload->[0]{mod_vers});
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

=item * C<module>

The name of a module to check for. Can be provided more than once.

=item * C<check_all_plugins>

A boolean, defaulting to false, indicating that all plugins being used to
build this distribution should be checked.

=back

=for Pod::Coverage mvp_multivalue_args mvp_aliases before_build before_release check_modules

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
