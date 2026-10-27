#!/usr/bin/env perl

# HTTP::VWF::Display::new() must refuse to build a page for a throttled client,
# and must not erase the throttle database when it does so.

use strict;
use warnings;

use FindBin qw($Bin);
use File::Spec;
use File::Temp qw(tempdir);
use Test::Most;

use lib File::Spec->catfile($Bin, '..', 'lib');

# Don't slow the test down; must be in place before HTTP::VWF::Display is compiled
BEGIN { *CORE::GLOBAL::sleep = sub { return 0 } }

use CGI::Info;
use HTTP::VWF::Display;
use YAML;

# A stand-in for CGI::Lingua: new() wants country(), HTML::SocialMedia
# asks for more, and undef is a good enough answer to the rest
{
	package StubLingua;
	our $AUTOLOAD;
	sub new { return bless { country => $_[1] }, $_[0] }
	sub country { return $_[0]{country} }
	sub AUTOLOAD { return }
	sub DESTROY { }
}

my $dir = tempdir(CLEANUP => 1);
my $db_file = File::Spec->catfile($dir, 'throttle');

# Config::Abstraction reads 'default' first
open(my $fout, '>', File::Spec->catfile($dir, 'default')) or die "$dir/default: $!";
print $fout <<"EOF";
<?xml version="1.0"?>
<config>
	<memory_cache><driver>Null</driver></memory_cache>
	<throttle>
		<file>$db_file</file>
		<max_items>2</max_items>
		<interval>90</interval>
	</throttle>
</config>
EOF
close $fout;

local $ENV{'CONFIG_DIR'} = $dir;
local $ENV{'REMOTE_ADDR'} = '10.1.2.3';
local $ENV{'REQUEST_METHOD'} = 'GET';
local $ENV{'HTTP_HOST'} = 'example.com';
delete local $ENV{'QUERY_STRING'};
delete local $ENV{'HTTP_REFERER'};

my @displays;
foreach (1..3) {
	CGI::Info->reset();
	my $info = CGI::Info->new();
	my $display = HTTP::VWF::Display->new(info => $info, lingua => StubLingua->new('GB'));
	push @displays, [ $display, $info ];
}

ok(defined($displays[0][0]), 'first request is served');
ok(defined($displays[1][0]), 'second request is served');
ok(!defined($displays[2][0]), 'third request, over the limit, is refused');
is($displays[2][1]->status(), 429, 'status is 429');
ok(-e $db_file, 'throttle database is kept');

# A store that cannot be used must survive, and the failure must be reported:
# deleting it throws away every other client's counters, and cannot repair a
# backend that is unusable.
{
	package RecordingLogger;
	our @calls;

	sub new { return bless {}, shift }
	sub _push { push @calls, [$_[0], join('', map { defined($_) ? $_ : '' } @_[1..$#_])] }

	# Written out rather than handled by AUTOLOAD, because callers ask can()
	sub debug { shift; _push('debug', @_) }
	sub info { shift; _push('info', @_) }
	sub notice { shift; _push('notice', @_) }
	sub warn { shift; _push('warn', @_) }
	sub error { shift; _push('error', @_) }
	sub trace { shift; _push('trace', @_) }
	sub DESTROY { }

	package main;
}

sub new_request {
	my ($logger) = @_;

	CGI::Info->reset();
	my $info = CGI::Info->new();
	my $display = HTTP::VWF::Display->new(
		info => $info,
		lingua => StubLingua->new('GB'),
		logger => $logger,
	);
	return ($display, $info);
}

subtest 'an unusable store is left alone and reported' => sub {
	# A path that no store can be opened at.  A read-only file will not do:
	# the backend opens the path for writing, and a test run as root - which
	# is what a container-based CI job does - is stopped by no file mode at
	# all.  It then rebuilds the store it could read and reports nothing, and
	# this test would pass for the wrong reason on one machine and fail on
	# another.  A directory cannot be opened for writing by anybody.
	my $store = File::Spec->catdir($dir, 'locked');
	mkdir($store, 0755) or die "mkdir $store: $!";
	@RecordingLogger::calls = ();

	my $display = HTTP::VWF::Display->new(
		info => CGI::Info->new(),
		lingua => StubLingua->new('GB'),
		logger => RecordingLogger->new(),
		config => { throttle => { file => $store, max_items => 2, interval => 90 } },
	);

	ok(defined($display), 'the request is still served');
	ok(-e $store, 'the store was not deleted');
	ok(scalar(grep { $_->[0] eq 'error' && $_->[1] =~ /Throttling is not working/ } @RecordingLogger::calls),
		'and the failure was reported at error level');
};

# A directory survives whatever happens to it - unlink() cannot remove one - so
# the store that must not be deleted is a file here, made read-only so that the
# backend cannot write it.  Root ignores file modes, and Windows reports a $>
# of 0 without having any root and does not keep its read-only attribute for the
# Unix mode, so where either applies there is no read-only store to offer and
# the directory above is all there is.
SKIP: {
	skip 'no read-only file to be had here', 1 if($> == 0);

	my $store = File::Spec->catfile($dir, 'read-only');
	open(my $fout, '>', $store) or die "$store: $!";
	print $fout "chain: {}\n";
	close($fout) or die "$store: $!";
	chmod(0444, $store) or die "chmod $store: $!";
	@RecordingLogger::calls = ();

	my $display = HTTP::VWF::Display->new(
		info => CGI::Info->new(),
		lingua => StubLingua->new('GB'),
		logger => RecordingLogger->new(),
		config => { throttle => { file => $store, max_items => 2, interval => 90 } },
	);

	ok($display && -e $store && (-s $store > 0),
		'a store that could not be written is served around, and left as it was');
};

subtest 'an unparsable store is rebuilt, not deleted' => sub {
	my $store = File::Spec->catfile($dir, 'corrupt');

	# Not a store at all: valid YAML, but a list rather than a bucket chain
	foreach my $rubbish ("{ this is not yaml", "- one\n- two\n") {
		open(my $fout, '>', $store) or die "$store: $!";
		print $fout $rubbish;
		close($fout) or die "$store: $!";

		my $display = HTTP::VWF::Display->new(
			info => CGI::Info->new(),
			lingua => StubLingua->new('GB'),
			config => { throttle => { file => $store, max_items => 2, interval => 90 } },
		);

		ok(defined($display), 'the request is served');
		ok(-e $store, 'the file is still there');

		my $data = eval { YAML::LoadFile($store) };
		is(ref($data), 'HASH', 'and has been replaced by a usable store');
	}
};

subtest 'a store with no bucket chain parameters is rebuilt without a word' => sub {
	my $store = File::Spec->catfile($dir, 'no-parameters');

	# A store that parses, and holds a chain, and has neither of the two
	# parameters Data::Throttler compares a store against.  Its chain restores
	# to a bucket chain, so the store looks reusable, and the chain is built
	# again either way - but the comparison it reaches is two undefined values
	# against the configured ones, which is a warning apiece and then the
	# parameters reported as changed.  Neither should be necessary.
	open(my $fout, '>', $store) or die "$store: $!";
	print $fout "chain: {}\n";
	close($fout) or die "$store: $!";

	my @warnings;
	local $SIG{__WARN__} = sub { push @warnings, $_[0] };

	my $display = HTTP::VWF::Display->new(
		info => CGI::Info->new(),
		lingua => StubLingua->new('GB'),
		config => { throttle => { file => $store, max_items => 2, interval => 90 } },
	);

	ok(defined($display), 'the request is served');

	is(scalar(grep { /uninitialized/ } @warnings), 0,
		'and no undefined value was warned about') or diag(@warnings);

	my $data = eval { YAML::LoadFile($store) };
	is(ref($data), 'HASH', 'the store was rebuilt in place');

	my $chain = (ref($data) eq 'HASH' && ref($data->{'chain'}) eq 'HASH') ? $data->{'chain'} : {};
	is($chain->{'max_items'}, 2, 'with the configured max_items on its chain');
	is($chain->{'interval'}, 90, 'and the configured interval');
};

done_testing();
