use strict;
use warnings;
use lib 'inc';
use ExtUtils::MakeMaker::Dist::Zilla::Develop;
WriteMakefile(
    NAME => 'Class::Load::XS',
    INSTALLMAN1DIR => 'none',
    INSTALLMAN3DIR => 'none',
);

