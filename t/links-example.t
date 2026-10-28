#!/usr/bin/env perl

# The links example, served: the request its front door makes, and the answer to it.
# F<examples/links.nigelhorne.com/index.html> sends a visitor to a short code of the
# site's own; this test takes the request out of that front door and runs it against
# the site the way the example's README runs it and the way its web server does - the
# site's own script, a program of its own, with the environment a request brings -
# and requires the request to be answered by the site: the code looked up in the
# site's own database, through the data module the site's own configuration names,
# and answered with what the database holds for it.  A front door whose code has no
# row, or a row that no longer says what the site answers, fails here rather than in
# a visitor's browser.
#
# Four requests are made of the site as it stands, so that the answer to the front
# door's code is worth something: the door's own request; a code the site has never
# heard of, which is the 404 the page documents; a request naming no code, the 400 it
# documents; and the door's code arriving from a crawler, which is the 402 it
# documents.  The last three are the controls, and they are what make the first an
# answer about the code rather than a blanket answer about the script.  A fifth - the
# page's other answer, a target fetched and served in the code's place - is made
# against a fixture of this test's own, in the section below.
#
# t/example-front-doors.t is the other half of this pair, and it is a reading of the
# site's files rather than a run of them: it checks the shape of the door - that the
# script it names is there, that the value it names is a key the site's database
# holds.  So a door that cannot be turned into a request is a skip here (that test
# reports it) rather than a second failure about the same fault; a door whose code
# the database does not hold is a failure here, because that is the request, run.
#
# Nothing here reaches the outside world.  The site's database maps its front door's code
# to the framework's F<github.com> page, and the page fetches what a code names: left
# alone, this test would depend on that page being fetchable, and would see 200 with
# somebody else's HTML on one run and 301 on the next.  The fetch is therefore made
# to fail, with the proxy settings LWP reads when C<PERL_LWP_ENV_PROXY> asks it to,
# pointed at port 0 of the loopback address - a port no server listens on - so that
# the request fails at once, without leaving the machine, and the answer is the one
# the page documents for a target it cannot fetch: a 301 to it.
#
# The page's other half is covered here too: a code whose target is fetched and served
# in its place, anchored at the target's origin - the scheme, host and port the code
# names - with a <base> element so that the target's own relative links still resolve,
# and with the site's own analytics in the head.  No row of the site's own database can be fetched from a test - its rows name
# the outside world - so that case needs a target of the test's own, a small HTTP
# server on the loopback address, and a database of the test's own: the site's own
# database with one row added, which a copy of the site's own configuration points the
# run at.  The script, the configuration and the page are the example's, so what that
# case exercises is the site, with one row it did not have.  Between them the two
# halves are the whole of the page, and of the whole path of the request - the front
# door's code, the site's configuration, its database module, the page, both of its
# answers, and the framework's own access log of them.
#
# The site is a FastCGI program for a Unix web server, as the framework's own page
# script is, so this test skips Windows rather than pretending to cover it there.

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Find ();
use File::Path qw(make_path);
use File::Slurp qw(read_file write_file);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin qw($Bin);
use IO::Socket::INET ();
use Test::Most;
use Text::xSV::Slurp;

# Under prove -t, $Bin is tainted; detaint it before it reaches a program name.
# The match is a statement of its own: with the match in the same expression as
# the declaration, warnings::unused counts the variable as unused, and the Linux
# workflow's sweep for unused variables fails the step on it.
my $root = do {
	my $dir = File::Spec->catdir($Bin, File::Spec->updir());
	$dir =~ /\A(.*)\z/s;
	abs_path($1);
};

my $example = File::Spec->catdir($root, 'examples', 'links.nigelhorne.com');
my $door = File::Spec->catfile($example, 'index.html');
my $conf = File::Spec->catdir($example, 'conf');

plan skip_all => "There is no links example to serve: $example" unless(-d $example);
plan skip_all => "The links example carries no front door: $door" unless(-f $door);
plan skip_all => "The links example carries no configuration in $conf"
	unless(grep { -f } glob(File::Spec->catfile($conf, '*')));
plan skip_all => 'Running the site\'s page script as a web server runs it is a Unix test'
	if($^O eq 'MSWin32');

# The file's contents.  The front door is one small file and the database is a CSV
# this test reads as a string, so neither needs a dependency to read.
sub slurp
{
	my $file = shift;

	open(my $fh, '<', $file) or return;
	local $/;
	return <$fh>;
}

# The values of a setting in a site's configuration, in either of the two forms a VWF
# configuration is written in: the plain C<key value> form, whose value is the rest of
# the line, and the XML form, whose value is the text of the element.  Several values
# are split the way the site's own script splits them, on whitespace and commas, and
# the file's comments are dropped first - this example's conf/ discusses several
# settings it does not use - so that a setting the site has commented out does not
# answer for the site.  A setting that is not there contributes nothing.
sub config_values
{
	my ($text, $key) = @_;

	$text =~ s{<!--.*?-->}{}gs;

	my $value;
	if($text =~ m{<\Q$key\E>\s*(.*?)\s*</\Q$key\E>}s) {	# the XML form
		$value = $1;
	} elsif($text =~ m{^[ \t]*\Q$key\E[ \t]+(\S.*)$}m) {	# the plain "key value" form
		$value = $1;
	}

	return defined($value) ? split(/[\s,]+/, $value) : ();
}

# Where the front door sends a visitor: the URL of its refresh, out of whichever meta
# element carries one.  t/example-front-doors.t reads the door the same way; the two
# tests read it for different purposes - that one for its shape, this one for the
# request to make - and each keeps its own reading, small as it is.
sub forward_url
{
	my $html = shift // '';

	foreach my $meta ($html =~ m{<meta\b[^>]*>}gi) {
		next unless($meta =~ m{http-equiv\s*=\s*["']?Refresh["']?}i);

		my ($content) = $meta =~ m{content\s*=\s*["']?([^"'>]+)}i;
		next unless(defined($content));

		my ($url) = $content =~ /\bURL\s*=\s*(\S+)/i;
		return $url if(defined($url));
	}

	return undef;
}

# The name the site is served under: the file in its own conf/ is named after the
# domain the request is made under - that is how the framework finds a site's
# configuration - so the request this test makes takes its F<Host> from there, and a
# site renamed the way the example's README says to rename it (rename the
# configuration file) keeps this test working.  A site configured in a file called
# F<default> is served under any name, and then the example's directory, which is the
# site's own name, is the one to use.
sub site_host
{
	my $default = File::Spec->catfile($conf, 'default');
	my ($named) = grep { $_ ne $default } glob(File::Spec->catfile($conf, '*'));

	return (File::Spec->splitpath($named))[2] if(defined($named));

	my @parts = File::Spec->splitdir($example);
	return $parts[-1];
}

# The rows of a CSV file, under the column names its header row gives them: the site's
# own database and the framework's access log are both read this way here, so that a
# quoted field stays one field - a location is a URL, and URLs have commas in them -
# and so that a database whose columns were renamed is a missing column rather than a
# site that quietly sent its visitors somewhere else.  A file that is not there, or
# that holds no rows, contributes none.
sub csv_rows
{
	my $file = shift;

	my $csv = slurp($file);
	return () unless(defined($csv) && length($csv));

	return @{ xsv_slurp(
		shape => 'aoh',
		text_csv => {
			sep_char => ',',
			allow_loose_quotes => 1,
		},
		string => \$csv,
	) || [] };
}

my $host = site_host();

# The site's own configuration: the file named after the domain it is served under -
# which is the name the framework looks for - or a F<default> file, which it reads
# under any name.  What is read here is the file's text, since the settings this test
# and its fixture need are the ones written in it rather than the ones in force: the
# run below is what reads them the framework's way.
my $config_name = (-f File::Spec->catfile($conf, $host)) ? $host : 'default';
my $config = slurp(File::Spec->catfile($conf, $config_name)) // '';

# Where the site keeps its databases: what its configuration says, in either of the
# two forms a VWF configuration is written in, or the framework's default, F<data/>
# beside F<cgi-bin/>, which is what this example's conf/ leaves unsaid and where it
# keeps its own.  A directory that is named but not there is still named: what this
# test is reading is the setting, and looking for the site's databases is what the run
# below does.
my ($configured_database_dir) = config_values($config, 'database_dir');
my $database_dir = defined($configured_database_dir)
	? $configured_database_dir
	: File::Spec->catdir($example, 'data');

# The site's database, as the site's own data module reads it: every CSV file under
# that directory, each with the header the file begins with.
my @database = map { csv_rows($_) } sort glob(File::Spec->catfile($database_dir, '*.csv'));

# The request the front door makes: the script the door names, and the query it asks
# for.  A door naming an address of its own, a path from the document root, a path
# out of the site, or a script that is not there, makes no request this test can make,
# and t/example-front-doors.t is where that is a failure - so this test skips, saying
# which door it was, rather than reporting the same fault twice.
my $forward = forward_url(slurp($door));

my ($path, $query) = defined($forward) ? split(/\?/, $forward, 2) : (undef, undef);
my $script = (defined($path) && ($path =~ /\A[\w.\/-]+\z/) && (index($path, '..') < 0))
	? File::Spec->catfile($example, split(m{/}, $path))
	: undef;

plan skip_all => 'The front door of the links example makes no request to run: '
	. (defined($forward) ? $forward : 'it forwards a visitor nowhere')
	unless(defined($script) && -f $script);

# The framework the run is to use: this checkout's own lib/, in front of whatever
# this test was given on @INC - the same tree, whatever way it was put there - and of
# the harness's own PERL5LIB, so that a run exercises the tree under test rather than
# an installed copy of the framework that may be older than it.
#
# It has to be given explicitly.  A child process inherits PERL5LIB but not the
# -Ilib a harness may have run this test with, and the site's own script puts its
# F<script_dir/../lib> on C<@INC> - which for this example is the site's page modules
# and not the framework, the two being separate trees here.  Without this,
# C<perl t/links-example.t>, which the README documents, would find no framework at
# all and the site would answer 500 rather than the codes this test is about.
my $perl5lib = join(':',
	File::Spec->catdir($root, 'lib'),
	(grep { -f File::Spec->catfile($_, 'HTTP', 'VWF.pm') } @INC),
	grep { length } split(/:/, $ENV{'PERL5LIB'} // ''),
);

subtest "the site's own database, in $database_dir" => sub {
	ok(scalar(@database), 'holds a row for a code to be looked up in');

	foreach my $column (qw(entry location)) {
		ok(scalar(@database) && exists($database[0]->{$column}),
			"its rows name the $column column, the code and where it sends the visitor");
	}
};

# The code the door's request is about, and the URL the site's own database holds for
# it: together they are what that request is to be answered with.  The database is
# the site's own, so a door naming a code it does not hold is a door to a 404, and a
# failure here rather than something to work around.  Its parameter's name is not
# read: which parameter the
# site's page looks its codes up in is the site's own business, and a door naming
# some other one is a request the page answers with the 400 it documents - which the
# case below reports as a failure to answer as the database says.
my (undef, $code) = defined($query) ? split(/=/, $query, 2) : (undef, undef);

my $location;
if(defined($code) && ($code ne '')) {
	my ($row) = grep { (($_->{'entry'} // '') eq $code) } @database;
	$location = $row ? $row->{'location'} : undef;
}

if(!defined($code) || ($code eq '')) {
	fail('the request the front door makes names a code for the site to look up');
	diag('it forwards the visitor to ', (defined($forward) ? $forward : 'nothing'));
} elsif(!defined($location)) {
	fail("the code in the request the front door makes, $forward, is one the site's database holds");
	diag("$database_dir holds: ",
		(join(' ', sort grep { defined($_) } map { $_->{'entry'} } @database) || '(no codes)'));
} else {
	# Everything a run writes goes into a directory of this test's own: HOME,
	# because the script puts F<~/lib/perl5> ahead of everything else on C<@INC>, and
	# a stale copy of the framework left in one would shadow the copy this test
	# asked for; TMPDIR, because the framework keeps its access
	# log, which this test reads back, in the temporary directory; and root_dir,
	# because it keeps its render buffer under that - not the site's own directory,
	# so that nothing here writes into the checkout, and one directory per case,
	# since two runs sharing one could answer each other's requests.  The site's own
	# configuration still sends its log to F</tmp/links.log>, which is where the
	# example's conf puts it and what a run of that site does.
	my $fixture = tempdir(CLEANUP => 1);

	# The requests to make, and what each is to be answered with.  The first is the
	# front door's own: the script it names, asked for the code it names.
	my $nosuchcode = 'nosuchcode';
	$nosuchcode .= 'x' while(grep { (($_->{'entry'} // '') eq $nosuchcode) } @database);

	my @cases = (
		{
			name => 'front-door',
			what => "the code the front door names, $code",
			args => [$query],
			status => '301 Moved Permanently',
			http_code => 301,
			body => "Moved to $location",
			location => $location,
			logged_args => $query,
		},
		{
			name => 'unknown-code',
			what => "a code the site has never heard of, $nosuchcode",
			args => ["entry=$nosuchcode"],
			status => '404 Not Found',
			http_code => 404,
			body => "Could not find $nosuchcode in the database",
			logged_args => "entry=$nosuchcode",
		},
		{
			name => 'no-code',
			what => 'a request that names no code at all',
			args => [],
			status => '400 Bad Request',
			http_code => 400,
			body => 'Invalid or missing entry parameter',
			logged_args => '',
		},
		{
			name => 'crawler',
			what => "the code the front door names, $code, arriving from a crawler",
			args => [$query],
			user_agent => 'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)',
			status => '402 Payment Required',
			http_code => 402,
			body => 'No links for crawlers',
			logged_args => $query,
		},
	);

	foreach my $case (@cases) {
		my $got = run($fixture, $case);

		subtest $case->{'what'} => sub {
			is($got->{'exit'}, 0, 'the script ran to completion') or diag($got->{'stderr'});
			like($got->{'stdout'}, qr/^Status: \Q$case->{'status'}\E\r?$/m,
				"the site answered $case->{'status'}");

			# Every answer this page gives is plain text it built itself: it
			# overrides C<as_string()>, where a page would otherwise split into
			# its headers and a rendered template, so none of the framework's
			# page furniture is in any of them.
			like($got->{'stdout'}, qr/^Content-Type: text\/plain; charset=UTF-8\r?$/m,
				'as plain text');
			like($got->{'stdout'}, qr/^Cache-Control: no-store\r?$/m,
				'that no cache is to keep');
			like($got->{'stdout'}, qr/^\Q$case->{'body'}\E\r?$/m,
				"saying: $case->{'body'}");
			# The list of pages is what this site's script would print if the page
			# it dispatches on defaulted to nothing - the framework's script
			# answers a request that names no page with it, and this site's is
			# the migration away from that.  Whichever script name the list came
			# out of, it is not an answer to a short URL, so any of them fails.
			unlike($got->{'stdout'}, qr{^/cgi-bin/\w+\.fcgi\?page=}m,
				'and not a list of pages, which this site has none of to offer');

			if(defined($case->{'location'})) {
				like($got->{'stdout'}, qr/^Location: \Q$case->{'location'}\E\r?$/m,
					"the visitor is sent to $case->{'location'}, the URL the site's own database holds for $code");
			} else {
				unlike($got->{'stdout'}, qr/^Location:/m,
					'nothing is followed for it: the answer offers no address');
			}

			# The framework's own record of the request: one line for it, with
			# the status it was answered with and the arguments it was made
			# with, so that a request answered before the framework saw it, or
			# not logged at all, fails here.
			check_logged($got, $case->{'logged_args'}, $case->{'http_code'});
		};
	}
}

# ── The page's other half: a code whose target is fetched and served ─────────
#
# The same page answers a code that is in the database by trying to fetch what it
# names: when that works and the target is an HTML page with a head, the target's page
# is served in the code's place, anchored at the target's origin so that the target's
# own relative links still resolve, with the site's own analytics added to the head.
# Nothing this example's database holds can be fetched from a test - its rows name the
# outside world - so the case is given a target and a database of its own: a small
# HTTP server on the loopback address, and the site's own database with one row added,
# which a copy of the site's own configuration points the run at.  The script, the
# page, the access control, the rate limiting and the access log are the example's
# own, so what is exercised is the site, with one row it did not have.
my $target_pid;
END {
	# The target is a process of this test's own, and a failing assertion ends a
	# subtest before the line that stops it, so it is not left to whatever the run
	# got as far as: a server left listening would outlive the test.
	kill('TERM', $target_pid) if($target_pid);
}

subtest 'a code whose target is fetched and served' => sub {
	# The database the page reads its codes from: the module the site's configuration
	# names under data_modules arrives at a page as the last part of its name, and
	# Database::Abstraction reads that part, lower-cased, as a F<.csv> file in the
	# directory the site's own configuration points at.  Each of the conditions below
	# is a skip rather than a failure, since each is a fault the cases above report
	# already - a site with no database for its page to read answers every code it
	# holds with a failure of its own - and a machine that will not let this test
	# listen on the loopback address is this test's environment, not the site's.
	my ($links_module) = grep { (split(/::/, $_))[-1] eq 'links' } config_values($config, 'data_modules');
	if(!defined($links_module)) {
		plan skip_all => 'The site names no links database for its page to read';
		return;
	}

	my $links_stem = lc((split(/::/, $links_module))[-1]);
	my $links_file = File::Spec->catfile($database_dir, "$links_stem.csv");
	if(!-r $links_file) {
		plan skip_all => "The site's database, $links_file, is not there to add a row to";
		return;
	}
	if(!scalar(@database)) {
		plan skip_all => "The site's database, $links_file, holds no rows to add one to";
		return;
	}
	if(!length($config)) {
		plan skip_all => "The site has no configuration, $config_name, to copy";
		return;
	}

	my $fixture = tempdir(CLEANUP => 1);
	my $fixture_conf = File::Spec->catdir($fixture, 'conf');
	my $fixture_data = File::Spec->catdir($fixture, 'data');
	make_path($fixture_conf, $fixture_data);

	# The target's page: a small document of the test's own, whose title and body are
	# what the site's answer must carry, and whose head is plain so that the base
	# element the site adds to it is the first thing in the head.
	my $target_page = <<'EOF';
<!DOCTYPE html>
<html>
<head>
<title>A page of the target's own</title>
</head>
<body>
<p>This is the target's own body.</p>
</body>
</html>
EOF

	my $target_path = '/target.html';
	my ($pid, $port, $target_log) = start_target($fixture, $target_page);
	$target_pid = $pid;
	if($port <= 0) {
		plan skip_all => "No target could be started for the fixture; see $target_log";
		return;
	}

	my $target_url = "http://127.0.0.1:$port$target_path";

	# The block the site's page injects into a page it serves on a target's behalf:
	# read from the site's source rather than written out here, so that what a served
	# page must carry and what the site injects cannot disagree, whatever the site
	# puts in it.
	my @injected = injected_block();
	ok(scalar(@injected), "the site's page injects content of its own into a page it serves");
	my $injected = $injected[0] // '';

	# The site's own settings, with that one setting among them: where the databases
	# are, pointing at the copy of them below rather than at the site's own directory,
	# which is what keeps this case from writing into the checkout.
	my $fixture_config = add_database_dir($config, $fixture_data);
	write_file(File::Spec->catfile($fixture_conf, $config_name), $fixture_config);

	# The database that configuration names: the site's own, with one row added for a
	# code of this test's own, naming the target above.  Both are read back below
	# rather than assumed, so that a copy that lost the site's rows, or a row that did
	# not land, is a failure here rather than a run that answers 404 for a reason
	# nobody can see.
	my $served_code = 'target';
	$served_code .= 'x' while(grep { (($_->{'entry'} // '') eq $served_code) } @database);

	my $fixture_database = slurp($links_file) // '';
	$fixture_database =~ s/\s*\z/\n/s;
	$fixture_database .= "$served_code,$target_url\n";

	my $fixture_database_file = File::Spec->catfile($fixture_data, "$links_stem.csv");
	write_file($fixture_database_file, $fixture_database);

	my @fixture_rows = csv_rows($fixture_database_file);
	my %held = map { ($_->{'entry'} // '') => 1 } @fixture_rows;
	my @lost = grep { !$held{$_} } grep { length } map { $_->{'entry'} // '' } @database;
	is_deeply(\@lost, [], "the fixture database is the site's own, every code of it held")
		or diag("the site's database holds: ", join(' ', sort keys %held));
	ok($held{$served_code}, "and $served_code, the code this case is about, is in it");

	# The request the case is about: that code, through the fixture's configuration.
	# It is the only case here whose answer is a target it has to reach, so it is the
	# only one run with nothing between it and the address it fetches.
	my $got = run($fixture, {
		name => 'served',
		args => ['entry=' . $served_code],
		config_dir => $fixture_conf,
		direct => 1,
	});

	subtest "the code $served_code, whose target is fetched" => sub {
		is($got->{'exit'}, 0, 'the script ran to completion') or diag($got->{'stderr'});
		like($got->{'stdout'}, qr/^Status: 200 OK\r?$/m, 'the site answered 200 OK');
		like($got->{'stdout'}, qr/^Content-Type: text\/html; charset=UTF-8\r?$/m,
			"as HTML, the target's own content type");
		unlike($got->{'stdout'}, qr/^Location:/m,
			'and not as a redirect: the target could be fetched, so the visitor is not sent to it');

		# The target's own page, rather than a rendering of one of the site's
		# templates: the title and the body it served are both in the answer.
		like($got->{'stdout'}, qr/<title>A page of the target's own<\/title>/,
			"the target's own title is served");
		like($got->{'stdout'}, qr/<p>This is the target's own body\.<\/p>/,
			'   and its own body');

		# The target's relative links, images and stylesheets are relative to the
		# target and not to this site, so the page is anchored at the target's
		# origin: the scheme, the host, and the port as well, since the target this
		# case fetches is served from a port of its own - an anchor without it would
		# send the target's own links to port 80.  (A target on the scheme's default
		# port is anchored without one, which is the other half of that rule and is
		# not reachable from here: a target with no port to fetch would have to be
		# listening on port 80.)  The anchor is the first thing in the head, where
		# it applies to everything in the document.
		my ($origin) = $target_url =~ m{\A(\w+://[^/]+)};
		like($got->{'stdout'}, qr{<head><base href="\Q$origin\E">},
			"the target's origin, $origin, is where the served page is anchored");

		# The site's own analytics, in the head, after the anchor and before the head
		# ends: the block the site's page carries, which is what makes a served page
		# the site's answer rather than only the target's.  It is compared with the
		# space between its pieces taken out, because the framework buffers the
		# answer and compacts it on the way out - the indentation and blank lines a
		# page is written with are not what the client is sent - so what the site
		# wrote is what is looked for, whitespace aside.
		my $page = without_space($got->{'stdout'});
		my $wanted = without_space($injected);
		my $at = $wanted eq '' ? -1 : index($page, $wanted);
		ok($at >= 0, "the site's own content is in the page it serves")
			or diag('the site injects: ', ($injected eq '' ? '(nothing)' : $injected));
		ok(($at >= 0) && ($at > index($page, '<base')) && ($at < index($page, '</head>')),
			'   inside the head, after the anchor and before the head ends');

		# The fetch the answer is: the target's server saw a request for the path
		# the code names, at the address it names, which is what makes this the
		# target's page rather than one of the site's own.
		my $seen = slurp($target_log) // '';
		like($seen, qr{^GET \Q$target_path\E HTTP/[\d.]+$}m,
			'the target was fetched, at the path the code names');
		like($seen, qr{^Host: 127\.0\.0\.1:\Q$port\E$}mi, '   at the address it names');

		check_logged($got, 'entry=' . $served_code, 200);
	};

	# The target is a process of this test's own rather than of the site's, so it is
	# stopped here: a run of this test leaves nothing listening.
	kill('TERM', $target_pid);
	waitpid($target_pid, 0);
	$target_pid = undef;

	return;
};

# A string as its content, whitespace aside.  The framework buffers a page and compacts
# it on the way out, so the indentation and blank lines the site writes its own content
# with are not what a client is sent: what the site put in a page is therefore looked
# for with the space between its pieces taken out, which is what the compaction leaves.
sub without_space
{
	my $text = shift // '';

	$text =~ s/\s+//g;
	return $text;
}

# The framework's own record of a request: one line for it, with the arguments it was
# made with and the status the site answered it with, so that a request answered before
# the framework saw it, or not logged at all, is a failure rather than a request this
# test never looked for.
sub check_logged
{
	my ($got, $args, $http_code) = @_;

	my @rows = csv_rows($got->{'log'});
	is(scalar(@rows), 1, 'the framework logged the request it answered')
		or return;

	is($rows[0]->{'args'}, $args, '   with the arguments the request was made with');
	is($rows[0]->{'http_code'}, $http_code, '   and the status the site answered it with');

	return;
}

# The site's own content, as its page module carries it: the block a page injects into
# a page it serves on a target's behalf.  It is read from the site's source rather than
# written out here, so that what a served page must carry and what the site injects
# cannot disagree, whatever the site puts in it.
sub injected_block
{
	my $dir = File::Spec->catdir($example, 'lib');
	return () unless(-d $dir);

	my @found;
	File::Find::find({
		wanted => sub {
			return unless(-f && /\.pm\z/);
			my $text = slurp($File::Find::name) // '';
			push(@found, $2) if($text =~ /\$INJECTED\s*=\s*<<\s*['"]?(\w+)['"]?;\n(.*?)\n\1/s);
		},
		no_chdir => 1,
	}, $dir);

	return @found;
}

# The site's configuration as a fixture needs it: the same settings, with the one
# setting that fixture adds - where the databases are - written among them.  A site
# that answered that question itself is answered for rather than left beside it: two
# elements of one name would leave the parser to decide which of them wins.  The
# file's comments are dropped, because the reader drops them as well - they are what a
# site says about its settings, while this is a copy of the settings - and because a
# commented-out setting is the one thing that would confuse the search for a setting
# to replace, this example's conf/ carrying a commented-out database_dir of its own.
# The setting is put where a setting belongs in the form the file is written in:
# inside C<E<lt>configE<gt>> for the XML form, and at the top of the file for the plain
# C<key value> form, which has no element for it to be inside of.
sub add_database_dir
{
	my ($text, $dir) = @_;

	$text =~ s{<!--.*?-->}{}gs;

	if(index($text, '</config>') >= 0) {	# the XML form
		unless($text =~ s{<database_dir>\s*.*?\s*</database_dir>}{<database_dir>$dir</database_dir>}s) {
			$text =~ s{</config>}{<database_dir>$dir</database_dir>\n</config>};
		}
		return $text;
	}

	unless($text =~ s{^[ \t]*database_dir[ \t]+.*$}{database_dir $dir}m) {
		$text = "database_dir $dir\n$text";
	}

	return $text;
}

# A target for the fixture: a small HTTP server of this test's own, on the loopback
# address, in a process of its own - the site fetches a target while this test waits
# for it, so nothing in this process can answer.  It serves the page it is given for
# every request, and writes down each request as it arrived, so that the site's answer
# can be tied to the fetch it made.  Returns the process to stop, the port it listens
# on, and the file it writes down to; a port of nothing but a body means it could not
# be started, and that file says why.
sub start_target
{
	my ($fixture, $page) = @_;

	my $log = File::Spec->catfile($fixture, 'target.log');
	pipe(my $reader, my $writer) or die "pipe: $!";

	my $pid = fork();
	defined($pid) or die "fork: $!";

	unless($pid) {
		# The child is a server of its own: nothing it writes is this test's output,
		# and the end-of-run bookkeeping it inherits would otherwise be written into
		# the file this test reads back.  What it writes is on the line as it arrives
		# rather than in a buffer, since it is stopped by a signal and a buffer never
		# flushed would take the record with it.
		close($reader);
		open(STDOUT, '>', $log) or exit 127;
		open(STDERR, '>&', \*STDOUT) or exit 127;
		$| = 1;

		my $listener = IO::Socket::INET->new(
			LocalAddr => '127.0.0.1',
			LocalPort => 0,		# whatever port the system gives it
			Proto => 'tcp',
			Listen => 5,
			ReuseAddr => 1,
		);
		if(!$listener) {
			print $writer "-1\n";
			close($writer);
			exit 1;
		}

		print $writer $listener->sockport(), "\n";
		close($writer);

		my $answer = "HTTP/1.0 200 OK\r\n" .
			"Content-Type: text/html; charset=UTF-8\r\n" .
			'Content-Length: ' . length($page) . "\r\n" .
			"Connection: close\r\n\r\n" .
			$page;

		while(my $conn = $listener->accept()) {
			# The request as it arrived - the request line and the headers,
			# which are what the caller asserts on - read in full before the
			# answer is written, so that the client is not still sending when the
			# connection closes.  Each line is written down under the line endings
			# the test is written from rather than the ones HTTP uses: what the
			# caller reads is where the request went, not how it was punctuated.
			while(my $line = <$conn>) {
				$line =~ s/\r\n\z/\n/;
				print $line;
				last if($line =~ /^\n\z/);
			}

			$conn->autoflush(1);
			print $conn $answer;
			close($conn);
		}

		exit 0;
	}

	close($writer);

	my $port = <$reader>;
	close($reader);
	$port = defined($port) ? $port : '';
	$port =~ s/\s+\z//;	# the line the child wrote, without its newline
	$port = ($port =~ /\A(\d+)\z/) ? $1 : -1;

	return ($pid, $port, $log);
}

# Run the script the front door names, the way a web server runs it - a program of
# its own, with the environment a request brings, and its output in files of its own
# rather than in this test's output - and return what it answered with, and where it
# was left.  What a request does not bring is removed first: a CONFIG_DIR or a
# CONFIG_FILE from the caller would send the run elsewhere for a site's
# configuration and read a file that is not the one its name should find, and a
# DOCUMENT_ROOT would change where it thinks its root is.
#
# The proxy settings are the fixture that keeps this off the network, and they are
# the last thing set: every C<*_proxy> variable the caller had is dropped, because
# LWP would otherwise have two answers for one setting - and warns about it - and
# because the ones a CGI request may not trust are the caller's, not this test's.  A
# case that asks for a target of the test's own, on the loopback address, is run with
# the proxy the other way round: none at all.
sub run
{
	my ($fixture, $case) = @_;

	my $dir = File::Spec->catdir($fixture, $case->{'name'});
	make_path($dir);

	my $out = File::Spec->catfile($dir, 'stdout');
	my $err = File::Spec->catfile($dir, 'stderr');

	local %ENV = (
		%ENV,
		HTTP_HOST => $host,
		REMOTE_ADDR => '127.0.0.1',
		REQUEST_METHOD => 'GET',
		HOME => $dir,
		TMPDIR => $dir,
		root_dir => $dir,
		PERL5LIB => $perl5lib,
	);

	delete @ENV{qw(QUERY_STRING HTTP_REFERER GATEWAY_INTERFACE CONFIG_DIR CONFIG_FILE DOCUMENT_ROOT)};
	delete @ENV{grep { /_proxy\z/i } keys %ENV};
	delete $ENV{'PERL_LWP_ENV_PROXY'};

	# A case that names a configuration directory of its own is run with it - that is
	# how the fixture below adds a row to the site's databases without writing into
	# the checkout - and one that does not is run with the caller's own removed, so
	# that the site is configured from where its own name says.
	$ENV{'CONFIG_DIR'} = $case->{'config_dir'} if($case->{'config_dir'});

	# A case whose answer is a target fetched and served has to be able to reach its
	# target, so it is run with no proxy at all and connects to the fixture's server
	# directly.  Every other case's answer is the redirect the page gives a target it
	# cannot fetch, and that is arranged rather than waited for: LWP reads these
	# settings only when PERL_LWP_ENV_PROXY asks it to, and port 0 of the loopback
	# address is a port nothing listens on, so the fetch fails at once and without
	# leaving the machine.  Both are set here rather than left to what the environment
	# had, since a proxy inherited from the caller would decide the answer instead.
	unless($case->{'direct'}) {
		$ENV{'PERL_LWP_ENV_PROXY'} = 1;
		$ENV{'http_proxy'} = $ENV{'https_proxy'} = 'http://127.0.0.1:0/';
		$ENV{'no_proxy'} = 'localhost,127.0.0.1';
	}

	if(defined($case->{'user_agent'})) {
		$ENV{'HTTP_USER_AGENT'} = $case->{'user_agent'};
	} else {
		# The absence of one is what leaves the script in its web-server mode
		# while keeping its own diagnostics on the standard error this test
		# reads back, rather than in a file of the run's.
		delete $ENV{'HTTP_USER_AGENT'};
	}

	my $pid = fork();
	defined($pid) or die "fork: $!";

	unless($pid) {
		open(STDOUT, '>', $out) or exit 127;
		open(STDERR, '>', $err) or exit 127;
		# exec does not return when it works; a failure reaches the child's
		# own standard error, which the caller reads back and diagnoses
		exec($^X, $script, @{$case->{'args'}}) or do {
			print STDERR "cannot run $script: $!\n";
			exit 127;
		};
	}

	waitpid($pid, 0);

	return {
		stdout => read_file($out, binmode => ':raw') // '',
		stderr => read_file($err, binmode => ':raw') // '',
		exit => $? == -1 ? -1 : $? >> 8,
		log => File::Spec->catfile($dir, 'vwf.log'),
	};
}

done_testing();
