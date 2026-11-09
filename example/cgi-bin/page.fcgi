#!/usr/bin/perl -w

# Can be tested at the command line, e.g.:
#	LANG=en_GB root_dir=$(pwd)/example perl -Ilib example/cgi-bin/page.fcgi
# To mimic a French mobile site:
#	root_dir=$(pwd)/example perl -Ilib example/cgi-bin/page.fcgi --mobile page=index lang=fr
# To turn off the linting of HTML on a search-engine landing page
#	root_dir=$(pwd)/example perl -Ilib example/cgi-bin/page.fcgi --search-engine page=index lint_content=0

use strict;
use warnings;
use autodie qw(:all);

use HTTP::VWF;

HTTP::VWF->new()->run();
