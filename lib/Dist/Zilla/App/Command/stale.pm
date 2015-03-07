use strict;
use warnings;
package Dist::Zilla::App::Command::stale;
# ABSTRACT: print your distribution's prerequisites and plugins that are out of date
# vim: set ts=8 sw=4 tw=78 et :

our $VERSION = '0.039';

use Dist::Zilla::App -command;
use List::Util 1.33 'any';
use List::MoreUtils 'uniq';
use Try::Tiny;
use Config::MVP::Section 2.200004 ();
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

    my @modules;

    # ugh, we need to do nearly a full build to get the prereqs
    # (this really should be abstracted better in Dist::Zilla::Dist::Builder)
    if ($all or any { $_->check_all_prereqs } @plugins)
    {
        $_->before_build for grep { not $_->isa('Dist::Zilla::Plugin::PromptIfStale') }
            @{ $zilla->plugins_with(-BeforeBuild) };
        $_->gather_files for @{ $zilla->plugins_with(-FileGatherer) };
        $_->set_file_encodings for @{ $zilla->plugins_with(-EncodingProvider) };
        $_->prune_files  for @{ $zilla->plugins_with(-FilePruner) };
        $_->munge_files  for @{ $zilla->plugins_with(-FileMunger) };
        $_->register_prereqs for @{ $zilla->plugins_with(-PrereqSource) };

        push @modules, map {
            ( $all || $_->check_all_prereqs ? $_->_modules_prereq : () ),
        } @plugins;
    }

    foreach my $plugin (@plugins)
    {
        push @modules,
            ( $all || $plugin->check_authordeps ? $plugin->_authordeps : () ),
            $plugin->_modules_extra,
            ( $all || $plugin->check_all_plugins ? $plugin->_modules_plugin : () );
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
        my @authordeps;

        # if a plugin or bundle tries to loads another module that isn't
        # installed or at the wrong version, catch it and add to the list of missing modules
        if (/\ACan't locate (\S+) .+ at \S+ line/
            or /^Compilation failed in require at (\S+) line/
            or /^(\S+) version \S+ required--this is only version \S+ at \S+ line/)
        {
            my $module = $1 || $2 || $3;
            $module =~ s{/}{::}g;
            $module =~ s{\.pm$}{};
            push @authordeps, $module;
        }
        else
        {
            push @authordeps, $1 if /Required plugin (\S+) isn't installed\./;

            # some plugins are not installed; need to run authordeps --missing
            die $_ unless
                m/Run 'dzil authordeps' to see a list of all required plugins/m
                or m/ version \(.+\) (does )?not match required version: /m;
        }

        push @authordeps, $self->_missing_authordeps;

        $self->app->chrome->logger->unmute;
        $self->log(join("\n", uniq sort @authordeps));

        undef;  # ensure $zilla = undef
    };

    return if not $zilla;

    my @stale_modules = try {
        $self->stale_modules($zilla, $opt->all);
    }
    catch {
        # if there was an error during the build, fall back to fetching
        # authordeps, in the hopes that we can report something helpful
        $self->_missing_authordeps;
    };

    $self->app->chrome->logger->unmute;
    $self->log(join("\n", @stale_modules));
}

sub _missing_authordeps
{
    my $self = shift;

    require Dist::Zilla::Util::AuthorDeps;
    Dist::Zilla::Util::AuthorDeps->VERSION(5.021);
    my @authordeps = map { (%$_)[0] }
        @{ Dist::Zilla::Util::AuthorDeps::extract_author_deps(
            '.',            # repository root
            1,              # --missing
          )
        };
}

1;

__END__

=pod

=head1 SYNOPSIS

  $ dzil stale --all | cpanm

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

=head1 SUPPORT

=for stopwords irc

Bugs may be submitted through L<the RT bug tracker|https://rt.cpan.org/Public/Dist/Display.html?Name=Dist-Zilla-Plugin-PromptIfStale>
(or L<bug-Dist-Zilla-Plugin-PromptIfStale@rt.cpan.org|mailto:bug-Dist-Zilla-Plugin-PromptIfStal@rt.cpan.org>).
I am also usually active on irc, as 'ether' at C<irc.perl.org>.

=head1 SEE ALSO

=for :list
* L<Dist::Zilla::Plugin::PromptIfStale>

=cut
