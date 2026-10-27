#!/usr/bin/env perl

# The smoke renders the Linux workflow used to run by hand, as a test: F<page.fcgi>
# run as a program, the way a web server runs it, for a page of the site's own, for
# the meta-data page this distribution ships, for a page asked for with an
# SQL-injection attempt in one of its parameters, and for an attempt to read a file
# outside the site.  The injection attempt is run from the command line as well,
# because that is the one way this program is run in which it reports what it is
# doing on STDOUT rather than through the log dispatcher - so it is the only place
# the framework's own account of the attempt can be pinned.  The security headers
# and the CSRF token cookie every page is served with are pinned by value, so that a
# weakened policy, a dropped header or a token that stopped being fresh on each load
# fails here.  The access log the script keeps - the line the workflow used to cat -
# is read back afterwards, so the requests are checked to have been recorded, one
# line each, with the page and the status they were served with.
#
# The site is one this test writes into a temporary directory: a configuration in
# CONFIG_DIR, a log path of its own choosing, no caches.  Nothing here depends on
# the machine's hostname, on F<~/lib/conf>, or on the checkout being writable.

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Path qw(make_path);
use File::Slurp qw(read_file write_file);
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
my $page_fcgi = File::Spec->catfile($root, 'cgi-bin', 'page.fcgi');

plan skip_all => "Cannot find a page.fcgi to render: $page_fcgi" unless(-f $page_fcgi);

# page.fcgi is a FastCGI program for a Unix web server: the meta-data page wants
# Filesys::Df, Sys::MemInfo and Sys::Uptime, and the escape case below asks for
# /etc/passwd.  The renders this test stands in for were run in the Linux
# workflow for the same reason.
plan skip_all => 'Rendering page.fcgi is a Unix web server test' if($^O eq 'MSWin32');

my $site_title = 'Page Render Test Site';

my $tmp  = tempdir(CLEANUP => 1);
my $conf = File::Spec->catdir($tmp, 'conf');
my $log  = File::Spec->catfile($tmp, 'vwf.log');

make_path($conf);

# The smallest site that renders: nothing cached, so that one render cannot be
# answered from another; a CSRF secret, so that the script has nothing to warn
# about; one language, so that the template it picks is predictable; and the log
# where this test can read it.  This is the fixture VWF's own render test writes
# too, apart from that language key: VWF's script offers en-gb by its own default
# rather than from its configuration, so the two cannot be the same file.
write_file(File::Spec->catfile($conf, 'default'), <<"CONFIG");
<?xml version="1.0"?>
<config>
\t<memory_cache><driver>Null</driver></memory_cache>
\t<disc_cache><driver>Null</driver></disc_cache>
\t<SiteTitle><English>$site_title</English><Default>$site_title</Default></SiteTitle>
\t<supported_languages>en-gb</supported_languages>
\t<vwflog>$log</vwflog>
\t<security>
\t\t<rate_limiting>
\t\t\t<max_requests>100</max_requests>
\t\t\t<max_requests_hard>150</max_requests_hard>
\t\t</rate_limiting>
\t\t<csrf><enable>1</enable><secret>page-render test</secret></csrf>
\t</security>
</config>
CONFIG

# Run the script the way a server would: a program of its own, with the
# environment a request brings, its output in files rather than in ours, and its
# own temporary directory for anything it writes on the side.
sub render_page {
	my @args = @_;

	return run_page(1, @args);
}

# Run the same program the other way it is run: from a command line, where it has
# no client address, logs what it does to STDOUT at debug level instead of through
# the log dispatcher, and stops after that one request.
sub render_page_from_command_line {
	my @args = @_;

	return run_page(0, @args);
}

sub run_page {
	my ($as_request, @args) = @_;

	(my $name = $args[0]) =~ s/[^A-Za-z0-9]/_/g;
	$name = "command-line-$name" unless($as_request);
	my $out = File::Spec->catfile($tmp, "$name.out");
	my $err = File::Spec->catfile($tmp, "$name.err");

	local %ENV = (
		%ENV,
		CONFIG_DIR => $conf,
		HTTP_ACCEPT_LANGUAGE => 'en-gb',
		REQUEST_METHOD => 'GET',
		HOME => $tmp,
		TMPDIR => $tmp,
		root_dir => $root,
	);
	delete @ENV{qw(QUERY_STRING HTTP_REFERER GATEWAY_INTERFACE)};

	if($as_request) {
		# A request brings the Host header and the address of the client that
		# made it; the script takes the absence of that address to mean it is
		# being run by hand, so these two are what put it on the path a web
		# server takes.
		$ENV{'HTTP_HOST'} = 'example.com';
		$ENV{'REMOTE_ADDR'} = '127.0.0.1';
	} else {
		delete @ENV{qw(HTTP_HOST REMOTE_ADDR)};
	}

	my $pid = fork();
	defined($pid) or die "fork: $!";

	unless($pid) {
		open(STDOUT, '>', $out) or exit 127;
		open(STDERR, '>', $err) or exit 127;
		# exec does not return when it works; what reaches the child after a
		# failure is its own standard error, which the caller reads back
		exec($^X, $page_fcgi, @args) or do {
			print STDERR "cannot run $page_fcgi: $!\n";
			exit 127;
		};
	}

	waitpid($pid, 0);

	return {
		stdout => read_file($out, binmode => ':raw') // '',
		stderr => read_file($err, binmode => ':raw') // '',
		exit => $? == -1 ? -1 : $? >> 8,
	};
}

# An SQL-injection attempt in a parameter, as the workflow's render passed one, in
# the query string's own encoding.
my $injection = 'Stock%20or%20(1,2)=(select*from(select%20'
	. 'name_const(CHAR(111,108,111,108,111,115,104,101,114),1),'
	. 'name_const(CHAR(111,108,111,108,111,115,104,101,114),1))a)%20--%20and%201=1';

# What each request is to do: the pages are rendered from a template of this
# distribution's, the path is a path rather than a page so it is refused, and the
# request carrying the injection attempt is answered with no page at all - see
# the case below.
my @cases = (
	{
		name => 'page=index',
		args => ['page=index'],
		kind => 'page',
		status => '200 OK',
		code => 200,
		template => 'index.tmpl',
		logged => 1,
	},
	{
		name => 'page=meta_data',
		args => ['page=meta_data'],
		kind => 'page',
		status => '200 OK',
		code => 200,
		template => 'meta_data.tmpl',
		logged => 1,
	},
	{
		name => 'page=/etc/passwd',
		args => ['page=/etc/passwd'],
		kind => 'refused',
		status => '403 Forbidden',
		code => 403,
		template => undef,
		logged => 1,
	},
	{
		name => 'page=upload, asked for with an SQL injection attempt',
		args => ['page=upload', "publish=$injection"],
		kind => 'blocked',
		status => undef,
		code => undef,
		template => undef,
		logged => 0,
	},
);

# The headers every page of this framework is served with, pinned by value: they
# are the defence-in-depth set HTTP::VWF::Display adds to the response.
my @security_headers = (
	['X-Frame-Options', 'SAMEORIGIN'],
	['X-Content-Type-Options', 'nosniff'],
	['X-XSS-Protection', '1; mode=block'],
	['Referrer-Policy', 'strict-origin-when-cross-origin'],
	['Content-Security-Policy', "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'"],
	['Strict-Transport-Security', 'max-age=31536000; includeSubDomains'],
);

# The CSRF token a page is served: the seconds it was made, 256 bits of entropy in
# hex, and a sha256 signature, in a cookie that no script can read and that is not
# sent from other sites.  Returns the token, or nothing if the page was not served
# one - the pages are then checked to have been served different ones.
sub csrf_token_in {
	my $out = shift;

	my ($token) = $out =~ /^Set-Cookie: csrf_token=([^\s;]+); path=\/; HttpOnly; SameSite=Strict\r?$/m;
	return undef unless(defined($token) && ($token =~ /\A\d+:[0-9a-f]{64}:[0-9a-f]{64}\z/));

	return $token;
}

my %csrf_token;

my %rendered = map { $_->{'name'} => render_page(@{$_->{'args'}}) } @cases;

foreach my $case (@cases) {
	my $got = $rendered{$case->{'name'}};

	subtest $case->{'name'} => sub {
		is($got->{'exit'}, 0, 'the script ran to completion')
			or diag($got->{'stderr'});

		if($case->{'kind'} eq 'blocked') {
			# The attempt is not served a page.  CGI::Info's parameter
			# handling refuses a value that looks like an injection, drops
			# the parameters with it - the page the request named among them
			# - and sets a non-200 status, over which the script declines to
			# answer: what it would have sent is the list of valid pages.
			unlike($got->{'stdout'}, qr/^Status: 200/m, 'no page was served');
			unlike($got->{'stdout'}, qr{</html>}, '   and nothing was rendered');
			unlike($got->{'stdout'}, qr{^/cgi-bin/page\.fcgi\?page=}m,
				'   nor the list of valid pages');

			return;
		}

		like($got->{'stdout'}, qr/^Status: \Q$case->{'status'}\E\r?$/m,
			"it answered $case->{'status'}");

		if($case->{'kind'} eq 'page') {
			like($got->{'stdout'}, qr/^Content-Type: text\/html/mi, 'it sent an HTML page');
			like($got->{'stdout'}, qr{</html>}, 'and rendered it to the end');

			foreach my $header (@security_headers) {
				my $count = () = $got->{'stdout'} =~ /^\Q$header->[0]\E: \Q$header->[1]\E\r?$/mg;
				is($count, 1, "it was served with $header->[0]: $header->[1]");
			}

			$csrf_token{$case->{'name'}} = csrf_token_in($got->{'stdout'});
			ok(defined($csrf_token{$case->{'name'}}),
				'and a CSRF token cookie: time, entropy in hex, signature, HttpOnly, SameSite=Strict');
		} else {
			# The point of the case: the file is not in the answer
			unlike($got->{'stdout'}, qr/^root:/m, '/etc/passwd was not served');
		}
	};
}

# The same request from the command line, the other way this program is run: there
# is no client address then, so the script reports what it does on STDOUT rather
# than through the log dispatcher, and the two things it says about the attempt -
# that there was no page to display, and that CGI::Info recorded the injection -
# can be pinned.  It must not be served a page either way.  VWF's own render test
# pins the same two messages.
subtest 'the SQL injection attempt, run from the command line' => sub {
	my $got = render_page_from_command_line('page=upload', "publish=$injection");

	is($got->{'exit'}, 0, 'the script ran to completion')
		or diag($got->{'stderr'});
	unlike($got->{'stdout'}, qr/^Status: 200/m, 'no page was served');
	unlike($got->{'stdout'}, qr{</html>}, '   and nothing was rendered');
	unlike($got->{'stdout'}, qr{^/cgi-bin/page\.fcgi\?page=}m,
		'   nor the list of valid pages');
	like($got->{'stdout'}, qr/Called with no page to display/, '   and the script said why');
	like($got->{'stdout'}, qr/SQL injection attempt blocked/,
		'   with the attempt recorded as blocked');
};

# A fresh token on every page load, as the framework says it issues: two pages
# served in the same run do not share one.  Both halves of that are checked: the
# tokens differ, and so do the 256 bits of entropy in the middle of them, which
# is the part that would be reused if the entropy had stopped being drawn per
# load - a difference in the time the tokens were made would hide that from a
# comparison of the tokens alone.  VWF's own render test checks the same pair.
{
	my @tokens = map { $csrf_token{$_->{'name'}} }
		grep { $_->{'kind'} eq 'page' } @cases;
	my @entropy = map { (split(/:/, $_ // ''))[1] } @tokens;

	isnt($tokens[0], $tokens[1], 'each page load is served a fresh CSRF token');
	isnt($entropy[0], $entropy[1], '   and its entropy is new, not the same token reissued');
}

# The title is one this test wrote, so seeing it on the page is the proof that
# the configuration this test wrote is the one the script read.
like($rendered{'page=meta_data'}->{'stdout'}, qr/\Q$site_title\E/,
	'the page carries the title from the site\'s configuration');

# The access log: one line per answered request, written for the refusals as well
# as for the pages.  A request refused for one of its parameters is dropped before
# a page is looked for, and is not among them.
subtest 'the access log' => sub {
	ok(-s $log, "the script wrote an access log to $log") or return;

	my @logged = grep { $_->{'logged'} } @cases;
	my $csv = read_file($log, err_mode => 'quiet') // '';
	my @rows = @{ xsv_slurp(
		shape => 'aoh',
		text_csv => {
			sep_char => ',',
			allow_loose_quotes => 1,
		},
		string => \$csv,
	) || [] };

	is(scalar(@rows), scalar(@logged), 'one line per answered request, and no others');

	# The columns the assertions below read, by name: a log that stopped carrying
	# one of them would otherwise fail only the request it belongs to.  VWF's own
	# render test reads the same four out of its header.
	foreach my $column (qw(http_code template args error)) {
		ok((defined($rows[0]) && exists($rows[0]->{$column})),
			"the log has a $column column");
	}

	is_deeply(
		[map { $_->{'args'} } @rows],
		[map { join('&', @{$_->{'args'}}) } @logged],
		'for the requests in the order they were made'
	);

	foreach my $case (@logged) {
		my $args = join('&', @{$case->{'args'}});
		my ($row) = grep { ($_->{'args'} // '') eq $args } @rows;

		ok($row, "$case->{'name'} is logged") or next;
		is($row->{'http_code'}, $case->{'code'}, "   with status $case->{'code'}");

		if(defined($case->{'template'})) {
			like($row->{'template'} || '', qr{\A\Q$root\E/templates/.*/\Q$case->{'template'}\E\z},
				'   and the template it was rendered from is this checkout\'s');
		} else {
			ok(!$row->{'template'}, '   with no template, since nothing was rendered');
			ok(length($row->{'error'} || ''), '   and a reason recorded');
		}
	}
};

done_testing();
