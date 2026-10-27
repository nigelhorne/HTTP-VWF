#!/usr/bin/env perl

# The smoke renders the Linux workflow used to run by hand, as a test: F<page.fcgi>
# run as a program, the way a web server runs it, for a page of the site's own, for
# the meta-data page this distribution ships, and for an attempt to read a file
# outside the site.  The access log the script keeps - the line the workflow used to
# cat - is read back afterwards, so the requests are checked to have been recorded,
# one line each, with the page and the status they were served with.
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
# where this test can read it.
write_file(File::Spec->catfile($conf, 'default'), <<"CONFIG");
<?xml version="1.0"?>
<config>
	<memory_cache><driver>Null</driver></memory_cache>
	<disc_cache><driver>Null</driver></disc_cache>
	<SiteTitle><English>$site_title</English><Default>$site_title</Default></SiteTitle>
	<supported_languages>en-gb</supported_languages>
	<vwflog>$log</vwflog>
	<security>
		<rate_limiting>
			<max_requests>100</max_requests>
			<max_requests_hard>150</max_requests_hard>
		</rate_limiting>
		<csrf><enable>1</enable><secret>page-render test</secret></csrf>
	</security>
</config>
CONFIG

# Run the script the way a server would: a program of its own, with the
# environment a request brings, its output in files rather than in ours, and its
# own temporary directory for anything it writes on the side.
sub render_page {
	my $page = shift;

	(my $name = $page) =~ s/[^A-Za-z0-9]/_/g;
	my $out = File::Spec->catfile($tmp, "$name.out");
	my $err = File::Spec->catfile($tmp, "$name.err");

	local %ENV = (
		%ENV,
		CONFIG_DIR => $conf,
		HTTP_HOST => 'example.com',
		HTTP_ACCEPT_LANGUAGE => 'en-gb',
		REMOTE_ADDR => '127.0.0.1',
		REQUEST_METHOD => 'GET',
		HOME => $tmp,
		TMPDIR => $tmp,
		root_dir => $root,
	);
	delete @ENV{qw(QUERY_STRING HTTP_REFERER GATEWAY_INTERFACE)};

	my $pid = fork();
	defined($pid) or die "fork: $!";

	unless($pid) {
		open(STDOUT, '>', $out) or exit 127;
		open(STDERR, '>', $err) or exit 127;
		# exec does not return when it works; what reaches the child after a
		# failure is its own standard error, which the caller reads back
		exec($^X, $page_fcgi, "page=$page") or do {
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

# What each page is to do: the two the site offers are rendered from a template
# of this distribution's, and the last is a path rather than a page, so it is
# refused rather than served.
my @cases = (
	{
		page => 'index',
		status => '200 OK',
		code => 200,
		template => 'index.tmpl',
	},
	{
		page => 'meta_data',
		status => '200 OK',
		code => 200,
		template => 'meta_data.tmpl',
	},
	{
		page => '/etc/passwd',
		status => '403 Forbidden',
		code => 403,
		template => undef,
	},
);

my %rendered = map { $_->{'page'} => render_page($_->{'page'}) } @cases;

foreach my $case (@cases) {
	my $page = $case->{'page'};
	my $got = $rendered{$page};

	subtest "page=$page" => sub {
		is($got->{'exit'}, 0, 'the script ran to completion')
			or diag($got->{'stderr'});

		like($got->{'stdout'}, qr/^Status: \Q$case->{'status'}\E\r?$/m,
			"it answered $case->{'status'}");

		if(defined($case->{'template'})) {
			like($got->{'stdout'}, qr/^Content-Type: text\/html/mi, 'it sent an HTML page');
			like($got->{'stdout'}, qr{</html>}, 'and rendered it to the end');
		} else {
			# The point of the case: the file is not in the answer
			unlike($got->{'stdout'}, qr/^root:/m, '/etc/passwd was not served');
		}
	};
}

# The title is one this test wrote, so seeing it on the page is the proof that
# the configuration this test wrote is the one the script read.
like($rendered{'meta_data'}->{'stdout'}, qr/\Q$site_title\E/,
	'the page carries the title from the site\'s configuration');

# The access log: one line per request, written for the refusals as well as for
# the pages.
subtest 'the access log' => sub {
	ok(-s $log, "the script wrote an access log to $log") or return;

	my $csv = read_file($log, err_mode => 'quiet') // '';
	my @rows = @{ xsv_slurp(
		shape => 'aoh',
		text_csv => {
			sep_char => ',',
			allow_loose_quotes => 1,
		},
		string => \$csv,
	) || [] };

	is(scalar(@rows), scalar(@cases), 'one line per request, and no others');
	is_deeply(
		[map { $_->{'args'} } @rows],
		[map { 'page=' . $_->{'page'} } @cases],
		'for the requests in the order they were made'
	);

	foreach my $case (@cases) {
		my $page = $case->{'page'};
		my ($row) = grep { ($_->{'args'} // '') eq "page=$page" } @rows;

		ok($row, "page=$page is logged") or next;
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
