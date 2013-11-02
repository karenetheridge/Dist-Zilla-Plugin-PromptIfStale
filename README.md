# NAME

Dist::Zilla::Plugin::PromptIfStale - Check at build/release time if modules are out of date

# VERSION

version 0.009

# SYNOPSIS

In your `dist.ini`:

    [PromptIfStale]
    phase = build
    module = Dist::Zilla
    module = Dist::Zilla::PluginBundle::Author::ME

or:

    [PromptIfStale]
    check_all_plugins = 1

# DESCRIPTION

`[PromptIfStale]` is a `BeforeBuild` or `BeforeRelease` plugin that compares the
locally-installed version of a module(s) with the latest indexed version,
prompting to abort the build process if a discrepancy is found.

Note that there is no effect on the built dist -- all actions are taken at
build time.

# OPTIONS

- `phase`

    Indicates whether the checks are performed at _build_ or _release_ time
    (defaults to _release_).

    (Remember that you can use different settings for different phases by employing
    this plugin twice, with different names.)

- `module`

    The name of a module to check for. Can be provided more than once.

- `check_all_plugins`

    A boolean, defaulting to false, indicating that all plugins being used to
    build this distribution should be checked.

- `check_all_prereqs`

    A boolean, defaulting to false, indicating that all prerequisites in the
    distribution metadata should be checked. The modules are a merged list taken
    from the `configure`, `build`, `runtime`, `test` and `develop` phases,
    and the `requires`, `recommends` and `suggests` types.

# SUPPORT

Bugs may be submitted through [the RT bug tracker](https://rt.cpan.org/Public/Dist/Display.html?Name=Dist-Zilla-Plugin-PromptIfStale)
(or [bug-Dist-Zilla-Plugin-PromptIfStale@rt.cpan.org](mailto:bug-Dist-Zilla-Plugin-PromptIfStale@rt.cpan.org)).
I am also usually active on irc, as 'ether' at `irc.perl.org`.

# SEE ALSO

- [Dist::Zilla::Plugin::Prereqs::MatchInstalled](http://search.cpan.org/perldoc?Dist::Zilla::Plugin::Prereqs::MatchInstalled), [Dist::Zilla::Plugin::Prereqs::MatchInstalled::All](http://search.cpan.org/perldoc?Dist::Zilla::Plugin::Prereqs::MatchInstalled::All)

# AUTHOR

Karen Etheridge <ether@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Karen Etheridge.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
