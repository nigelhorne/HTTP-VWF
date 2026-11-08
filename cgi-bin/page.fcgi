#!/usr/bin/perl -w

use strict;
use warnings;
use autodie qw(:all);

use HTTP::VWF;

my $page = HTTP::VWF->new();
$page->run();
