use strict;
use warnings;
use lib 'inc';
use ExtUtils::MakeMaker::Dist::Zilla::Develop;
WriteMakefile(
    NAME => 'Dist::Zilla::Plugin::PromptIfStale',
    INSTALLMAN1DIR => 'none',
    INSTALLMAN3DIR => 'none',
);

