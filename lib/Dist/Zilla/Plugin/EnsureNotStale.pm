use strict;
use warnings;
package Dist::Zilla::Plugin::EnsureNotStale;
# ABSTRACT: Abort at build/release time if modules are out of date
# vim: set ts=8 sts=4 sw=4 tw=115 et :

our $VERSION = '0.046';

use Moose;
extends 'Dist::Zilla::Plugin::PromptIfStale';
use namespace::autoclean;

has '+fatal' => (
    init_arg => undef,  # cannot be passed in as a config value
    default => 1,
);

__PACKAGE__->meta->make_immutable;
__END__

=pod

=head1 SYNOPSIS

In your F<dist.ini>:

    [EnsureNotStale]

=head1 DESCRIPTION

This is a L<Dist::Zilla> plugin that behaves just like
L<[PromptIfStale]|Dist::Zilla::Plugin::PromptIfStale> would with its C<fatal>
option set to true. Therefore, if there are any stale modules found, the build
or release is aborted immediately.

=head1 CONFIGURATION OPTIONS

All options are as for L<[PromptIfStale]|Dist::Zilla::Plugin::PromptIfStale>,
except C<fatal> cannot be passed or set (it is always true).

=head1 SUPPORT

=for stopwords irc

Bugs may be submitted through L<the RT bug tracker|https://rt.cpan.org/Public/Dist/Display.html?Name=Dist-Zilla-Plugin-PromptIfStale>
(or L<bug-Dist-Zilla-Plugin-PromptIfStale@rt.cpan.org|mailto:bug-Dist-Zilla-Plugin-PromptIfStale@rt.cpan.org>).
I am also usually active on irc, as 'ether' at C<irc.perl.org>.

=head1 ACKNOWLEDGEMENTS

Getty made me do this!

=head1 SEE ALSO

=for :list
* the L<[PromptIfStale]|Dist::Zilla::Plugin::PromptIfStale> plugin in this distribution
* the L<dzil stale|Dist::Zilla::App::Command::stale> command in this distribution
* L<Dist::Zilla::Plugin::Prereqs::MatchInstalled>, L<Dist::Zilla::Plugin::Prereqs::MatchInstalled::All>

=cut
