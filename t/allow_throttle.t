#!/usr/bin/env perl

# HTTP::VWF::Allow throttles as well as HTTP::VWF::Display does, so it follows
# the same policy when the store cannot be used: the request is served, the
# store is left alone, and the failure is reported at error level.  A store that
# can be used must still refuse an abusive client, so that serving a request
# because the store is unusable is not the same as never throttling anybody.
# See "WHEN THE STORE CANNOT BE USED" in HTTP::VWF::Throttle.

use strict;
use warnings;

use FindBin qw($Bin);
use File::Spec;
use File::Temp qw(tempdir);
use Test::Most;

use lib File::Spec->catfile($Bin, '..', 'lib');

use CGI::Info;
use Data::Throttler;
use HTTP::VWF::Allow;
use HTTP::VWF::Throttle;	# Defines the 'VWF' backend Data::Throttler asks for

# Stands in for the DShield cache: a non-empty entry for today means allow()
# reads the feed from the cache and never goes near the network
{
	package StubCache;

	sub new { return bless {}, shift }
	sub get { return '1.2.3.4' }
	sub set { return 1 }
	sub remove { return 1 }
}

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
}

my $dir = tempdir(CLEANUP => 1);

local $ENV{'REMOTE_ADDR'} = '10.10.10.1';
local $ENV{'REQUEST_METHOD'} = 'GET';
local $ENV{'HTTP_HOST'} = 'example.com';
delete local $ENV{'QUERY_STRING'};
delete local $ENV{'HTTP_REFERER'};
delete local $ENV{'HTTP_USER_AGENT'};

sub allow_from {
	my ($addr, %args) = @_;

	$ENV{'REMOTE_ADDR'} = $addr;
	CGI::Info->reset();
	my $info = CGI::Info->new();

	my $allowed = eval {
		HTTP::VWF::Allow::allow({
			info => $info,
			cache => StubCache->new(),
			logger => $args{'logger'},
			config => $args{'config'},
		});
	};

	return ($allowed, $@, $info);
}

subtest 'a store that cannot be used does not refuse the client' => sub {
	# A path that no store can be opened at.  A read-only file will not do:
	# the backend opens the path for writing, and a test run as root - which is
	# what a container-based CI job does - is stopped by no file mode at all,
	# so the failure this subtest is about never happens.  A directory cannot
	# be opened for writing by anybody.
	my $store = File::Spec->catdir($dir, 'unusable');
	mkdir($store, 0755) or die "mkdir $store: $!";
	@RecordingLogger::calls = ();

	my ($allowed, $error) = allow_from('10.10.10.1',
		logger => RecordingLogger->new(),
		config => { throttle => { file => $store, max_items => 2, interval => 90 } },
	);

	# The failure has to be the store, not something else the eval caught
	my $reported = scalar grep { $_->[0] eq 'error' && ($_->[1] =~ /Throttling is not working/) && ($_->[1] =~ /\Q$store\E/) }
		@RecordingLogger::calls;

	ok($allowed, 'the request is served');
	ok(!$error, 'and nothing was thrown at the caller');
	ok(-e $store, 'the store was not deleted');
	ok($reported, 'and the failure was reported at error level');
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

	my ($allowed, $error) = allow_from('10.10.10.3',
		logger => RecordingLogger->new(),
		config => { throttle => { file => $store, max_items => 2, interval => 90 } },
	);

	ok($allowed && !$error && -e $store && (-s $store > 0),
		'a store that could not be written is served around, and left as it was');
};

subtest 'a store that can be used still refuses an abusive client' => sub {
	my $store = File::Spec->catfile($dir, 'working');
	my $addr = '10.10.10.2';

	# Fill this client's bucket, as an earlier request would have done
	my $throttler = Data::Throttler->new(
		max_items => 1,
		interval => 90,
		backend => 'VWF',
		backend_options => { db_file => $store },
	);
	ok($throttler->try_push(key => $addr), 'the store holds one request for the client');

	@RecordingLogger::calls = ();
	my ($allowed, $error, $info) = allow_from($addr,
		logger => RecordingLogger->new(),
		config => { throttle => { file => $store, max_items => 1, interval => 90 } },
	);

	my $warned = scalar grep { $_->[0] eq 'warn' && $_->[1] =~ /has been throttled/ }
		@RecordingLogger::calls;

	ok(!$allowed, 'the client is refused');
	ok(ref($error) && $error->isa('Error'), 'as a deliberate denial, not a failure of the store');
	is($info->status(), 429, 'with a 429');
	ok($warned, 'and a warning');
	ok(-e $store, 'the store is kept');
};

done_testing();
