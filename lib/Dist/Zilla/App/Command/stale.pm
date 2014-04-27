use strict;
use warnings;
package Dist::Zilla::App::Command::stale;
# ABSTRACT: print your distribution's prerequisites and plugins that are out of date

use Dist::Zilla::App -command;
use List::MoreUtils 'uniq';
use Try::Tiny;
use namespace::autoclean;

sub abstract { "print your distribution's stale prerequisites and plugins" }

sub opt_spec
{
    [ 'all'   , 'check all plugins and prerequisites, regardless of plugin configuration' ]
    # TODO?
    # [ 'plugins', 'check all plugins' ],
    # [ 'prereqs', 'check all prerequisites' ],
}

sub stale_modules
{
    my ($self, $zilla, $all) = @_;

    my @plugins = grep { $_->isa('Dist::Zilla::Plugin::PromptIfStale') } @{ $zilla->plugins };
    if (not @plugins)
    {
        require Dist::Zilla::Plugin::PromptIfStale;
        push @plugins,
            Dist::Zilla::Plugin::PromptIfStale->new(zilla => $zilla, plugin_name => 'stale_command');
    }

    my @modules = map {
        $_->_modules_extra,
        ( $all || $_->check_all_plugins ? $_->_modules_plugin : () ),
    } @plugins;

    # ugh, we need to do nearly a full build to get the prereqs
    # (this really should be abstracted better in Dist::Zilla::Dist::Builder)
    if ($all or grep { $_->check_all_prereqs } @plugins)
    {
        $_->before_build for grep { not $_->isa('Dist::Zilla::Plugin::PromptIfStale') }
            @{ $zilla->plugins_with(-BeforeBuild) };
        $_->gather_files for @{ $zilla->plugins_with(-FileGatherer) };
        $_->set_file_encodings for @{ $zilla->plugins_with(-EncodingProvider) };
        $_->prune_files  for @{ $zilla->plugins_with(-FilePruner) };
        $_->munge_files  for @{ $zilla->plugins_with(-FileMunger) };
        $_->register_prereqs for @{ $zilla->plugins_with(-PrereqSource) };

        push @modules, $plugins[0]->_modules_prereq;
    }

    return if not @modules;

    my ($stale_modules, undef) = $plugins[0]->stale_modules(uniq @modules);
    return @$stale_modules;
}

sub execute
{
    my ($self, $opt) = @_; # $arg

    $self->app->chrome->logger->mute unless $self->app->global_options->verbose;

    my $zilla = try {
        # parse dist.ini and load, instantiate all plugins
        $self->zilla;
    }
    catch {
        die $_ unless
            m/Run 'dzil authordeps' to see a list of all required plugins/m
            or m/ version \(.+\) (does )?not match required version: /m;

        # some plugins are not installed; running authordeps --missing...

        my @authordeps = $self->_get_authordeps;

        $self->app->chrome->logger->unmute;
        $self->log(join("\n", @authordeps));

        undef;  # ensure $zilla = undef
    };

    return if not $zilla;

    my @stale_modules = try {
        $self->stale_modules($zilla, $opt->all);
    }
    catch {
        # if there was an error during the build, fall back to fetching
        # authordeps, in the hopes that we can report something helpful
        $self->_get_authordeps;
    };

    $self->app->chrome->logger->unmute;
    $self->log(join("\n", @stale_modules));
}

sub _get_authordeps
{
    my $self = shift;

    require Dist::Zilla::Util::AuthorDeps;
    require Path::Class;
    my @authordeps = map { (%$_)[0] }
        @{ Dist::Zilla::Util::AuthorDeps::extract_author_deps(
            Path::Class::dir('.'),  # ugh!
                1,                  # --missing
           ) };
}

1;

__END__

=pod

=head1 SYNOPSIS

  $ dzil stale | cpanm

=head1 DESCRIPTION

This is a command plugin for L<Dist::Zilla>. It provides the C<stale> command,
which acts as L<[PromptIfStale]|Dist::Zilla::Plugin::PromptIfStale> would
during the build: compares the locally-installed version of a module(s) with
the latest indexed version, and print all modules that are thus found to be
stale.  You could pipe that list to a CPAN client like L<cpanm> to update all
of the modules in one quick go.

When a L<[PromptIfStale]|Dist::Zilla::Plugin::PromptIfStale> configuration is
present in F<dist.ini>, its configuration is honoured (unless C<--all> is
used); if there is no such configuration, behaviour is as for C<--all>.

=head1 OPTIONS

=head2 --all

Checks all plugins and prerequisites (as well as any additional modules listed
in a local L<[PromptIfStale]|Dist::Zilla::Plugin::PromptIfStale>
configuration, if there is one).

=for Pod::Coverage stale_modules

=cut
