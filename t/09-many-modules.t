use strict;
use warnings FATAL => 'all';

# same as t/08, except we don't fake our way past half the functionality

use Test::More;
plan skip_all => 'this test downloads a large file from the CPAN and should only be run for authors'
    unless $ENV{AUTHOR_TESTING} or -d '.git';

use lib 't/lib';
use ManyModules;
ManyModules->do_tests;

done_testing;
