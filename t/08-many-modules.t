use strict;
use warnings FATAL => 'all';

use Test::More;
use Moose::Util 'find_meta';

# ensure we don't actually make network hits
{
    use HTTP::Tiny;
    my $meta = find_meta('HTTP::Tiny')
        || Class::MOP::Class->initialize('HTTP::Tiny');
    $meta->add_around_method_modifier(mirror => sub { +{ success => 1 } });
}
{
    use Parse::CPAN::Packages::Fast;
    my $meta = find_meta('Parse::CPAN::Packages::Fast')
        || Class::MOP::Class->initialize('Parse::CPAN::Packages::Fast');
    my $initialized;
    $meta->add_around_method_modifier(new => sub {
        die if $initialized;
        'fake packages object ' . $initialized++;
    });
}

use lib 't/lib';
use ManyModules;
ManyModules->do_tests;

done_testing;
