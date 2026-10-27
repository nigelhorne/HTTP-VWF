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
# Four requests are made, so that the answer to the front door's code is worth
# something: the door's own request; a code the site has never heard of, which is the
# 404 the page documents; a request naming no code, the 400 it documents; and the
# door's code arriving from a crawler, which is the 402 it documents.  The last three
# are the controls, and they are what make the first an answer about the code rather
# than a blanket answer about the script.
#
# t/example-front-doors.t is the other half of this pair, and it is a reading of the
# site's files rather than a run of them: it checks the shape of the door - that the
# script it names is there, that the value it names is a key the site's database
# holds.  So a door that cannot be turned into a request is a skip here (that test
# reports it) rather than a second failure about the same fault; a door whose code
# the database does not hold is a failure here, because that is the request, run.
#
# Nothing here reaches the network.  The site's database maps its front door's code
# to the framework's F<github.com> page, and the page fetches what a code names: left
# alone, this test would depend on that page being fetchable, and would see 200 with
# somebody else's HTML on one run and 301 on the next.  The fetch is therefore made
# to fail, with the proxy settings LWP reads when C<PERL_LWP_ENV_PROXY> asks it to,
# pointed at port 0 of the loopback address - a port no server listens on - so that
# the request fails at once, without leaving the machine, and the answer is the one
# the page documents for a target it cannot fetch: a 301 to it.  The other half of
# the page, a code whose target is fetched and served in its place, needs a target
# for the test to fetch and so a database of the test's own, and is not covered here;
# what is covered is the whole path of the request - the front door's code, the
# site's configuration, its database module, the page, the answer, and the
# framework's own access log of it.
#
# The site is a FastCGI program for a Unix web server, as the framework's own page
# script is, so this test skips Windows rather than pretending to cover it there.

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Path qw(make_path);
use File::Slurp qw(read_file);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin qw($Bin);
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

# Where the site keeps its databases: what its configuration says, in either of the
# two forms a VWF configuration is written in, or the framework's default, F<data/>
# beside F<cgi-bin/>, which is what this example's conf/ leaves unsaid and where it
# keeps its own.  The configuration's comments are dropped first, as
# t/example-front-doors.t drops them, so that a setting the site has commented out -
# this example's conf/ discusses several it does not use - does not answer for the
# site.  A directory that is named but not there is still named: what this test is
# reading is the setting, and looking for the site's databases is what the run below
# does.
my $database_dir = do {
	my $config = slurp(File::Spec->catfile($conf, $host)) // slurp(File::Spec->catfile($conf, 'default')) // '';
	$config =~ s{<!--.*?-->}{}gs;

	my $dir;
	if($config =~ m{<database_dir>\s*(.*?)\s*</database_dir>}s) {
		$dir = $1;
	} elsif($config =~ m{^[ \t]*database_dir[ \t]+(\S+)}m) {	# the plain "key value" form
		$dir = $1;
	}

	(defined($dir) && length($dir))
		? $dir
		: File::Spec->catdir($example, 'data');
};

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
			my @rows = csv_rows($got->{'log'});
			is(scalar(@rows), 1, 'the framework logged the request it answered')
				or return;

			is($rows[0]->{'args'}, $case->{'logged_args'},
				'   with the arguments the request was made with');
			is($rows[0]->{'http_code'}, $case->{'http_code'},
				'   and the status the site answered it with');
		};
	}
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
# because the ones a CGI request may not trust are the caller's, not this test's.
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

	$ENV{'PERL_LWP_ENV_PROXY'} = 1;
	$ENV{'http_proxy'} = $ENV{'https_proxy'} = 'http://127.0.0.1:0/';
	$ENV{'no_proxy'} = 'localhost,127.0.0.1';

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
