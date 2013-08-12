use strict;
use warnings;
package Dist::Zilla::Plugin::PromptIfStale;
# ABSTRACT: ...

use Moose;
with 'Dist::Zilla::Role::BeforeBuild';

use MooseX::Types::Moose qw(ArrayRef Bool);
use MooseX::Types::LoadableClass 'LoadableClass';
use List::MoreUtils 'uniq';
use Module::Runtime 'use_module';
use version;
use HTTP::Tiny;
use Encode;
use JSON;

sub mvp_multivalue_args { 'modules' }
sub mvp_aliases { { module => 'modules' } }

has modules => (
    isa => ArrayRef[LoadableClass],
    traits => [ 'Array' ],
    handles => { modules => 'elements' },
    lazy => 1,
    default => sub { [] },
);

has check_all => (
    is => 'ro', isa => Bool,
    default => 0,
);

sub before_build
{
    my $self = shift;

    my @modules = $self->check_all
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
    return (0, 'index could not be queried?') if not $res->{success};

    # JSON wants UTF-8 bytestreams, so we need to re-encode no matter what
    # encoding we got. -- rjbs, 2011-08-18 (in Dist::Zilla)
    my $json_octets = Encode::encode_utf8($res->{content});
    my $payload = JSON::->new->decode($json_octets);

    return undef unless \@$payload;
    return undef if not defined $payload->[0]{mod_vers};
    version->parse($payload->[0]{mod_vers});
}

__PACKAGE__->meta->make_immutable;
__END__

=pod

=head1 SYNOPSIS

    use Dist::Zilla::Plugin::PromptIfStale;

    ...

=head1 DESCRIPTION

...

=head1 FUNCTIONS/METHODS

=over 4

=item * C<foo>

...

=back

=head1 SUPPORT

=for stopwords irc

Bugs may be submitted through L<the RT bug tracker|https://rt.cpan.org/Public/Dist/Display.html?Name=Dist-Zilla-Plugin-PromptIfStale>
(or L<bug-Dist-Zilla-Plugin-PromptIfStale@rt.cpan.org|mailto:bug-Dist-Zilla-Plugin-PromptIfStale@rt.cpan.org>).
I am also usually active on irc, as 'ether' at C<irc.perl.org>.

=head1 ACKNOWLEDGEMENTS

...

=head1 SEE ALSO

=begin :list

* L<foo>

=end :list

=cut
