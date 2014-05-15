# NAME

Dist::Zilla::Plugin::PromptIfStale - Check at build/release time if modules are out of date

# VERSION

version 0.023

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

- `check_authordeps`

    A boolean, defaulting to false, indicating that all authordeps in `dist.ini`
    (like what is done by `dzil authordeps`) should be checked.

    As long as this option is not explicitly set to false, a check is always made
    for authordeps being installed (but the indexed version is not checked). This
    serves as a fast way to guard against a build blowing up later through the
    inadvertent lack of fulfillment of an explicit `; authordep` declaration.

- `check_all_plugins`

    A boolean, defaulting to false, indicating that all plugins being used to
    build this distribution should be checked.

- `check_all_prereqs`

    A boolean, defaulting to false, indicating that all prerequisites in the
    distribution metadata should be checked. The modules are a merged list taken
    from all phases (`configure`, `build`, `runtime`, `test` and `develop`) ,
    and the `requires`, `recommends` and `suggests` types.

- `skip`

    The name of a module to exempt from checking. Can be provided more than once.

- `fatal`

    A boolean, defaulting to false, indicating that missing prereqs will result in
    an immediate abort of the build/release process, without prompting.

- `index_base_url`

    When provided, uses this base URL to fetch `02packages.details.txt.gz`
    instead of the default `http://www.cpan.org`.  Use this when your
    distribution uses prerequisites found only in your darkpan-like server.

# METHODS

## stale\_modules

Given a list of modules to check, returns

- a list reference of modules that are stale (not installed or the version is not at least the latest indexed version
- a list reference of error messages describing the issues found

# SUPPORT

Bugs may be submitted through [the RT bug tracker](https://rt.cpan.org/Public/Dist/Display.html?Name=Dist-Zilla-Plugin-PromptIfStale)
(or [bug-Dist-Zilla-Plugin-PromptIfStale@rt.cpan.org](mailto:bug-Dist-Zilla-Plugin-PromptIfStale@rt.cpan.org)).
I am also usually active on irc, as 'ether' at `irc.perl.org`.

# SEE ALSO

- the [\[EnsureNotStale\]](https://metacpan.org/pod/Dist::Zilla::Plugin::EnsureNotStale) plugin in this distribution
- the [dzil stale](https://metacpan.org/pod/Dist::Zilla::App::Command::stale) command in this distribution
- [Dist::Zilla::Plugin::Prereqs::MatchInstalled](https://metacpan.org/pod/Dist::Zilla::Plugin::Prereqs::MatchInstalled), [Dist::Zilla::Plugin::Prereqs::MatchInstalled::All](https://metacpan.org/pod/Dist::Zilla::Plugin::Prereqs::MatchInstalled::All)

# AUTHOR

Karen Etheridge <ether@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Karen Etheridge.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

# CONTRIBUTOR

David Golden <dagolden@cpan.org>
