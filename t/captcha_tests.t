#!/usr/bin/env perl

# The tests here need no mocking library: the handles the page is built from
# are real objects of the framework's own, and the one thing that cannot be
# built for real - a request to a site that is not there - is answered by a
# configuration of this test's own in a temporary CONFIG_DIR.

use strict;
use warnings;
use Test::More;
use CGI::Info;
use CGI::Lingua;
use FindBin qw($Bin);
use File::Spec;
use File::Temp qw(tempdir);

# Add lib paths
use lib File::Spec->catfile($Bin, '..', 'lib');
use lib File::Spec->catfile($Bin, 'lib');
use lib 'lib';

BEGIN { 
	use_ok('HTTP::VWF::CAPTCHA');
	use_ok('HTTP::VWF::Display::captcha');
}

subtest 'CAPTCHA module initialization' => sub {
	plan tests => 3;
	
	my $captcha = HTTP::VWF::CAPTCHA->new(
		site_key => 'test_site_key',
		secret_key => 'test_secret_key'
	);
	
	ok($captcha, 'CAPTCHA object created');
	is($captcha->get_site_key(), 'test_site_key', 'Site key accessible');
	isa_ok($captcha, 'HTTP::VWF::CAPTCHA');
};

subtest 'Display module initialization' => sub {
	plan tests => 2;
	
	# HTTP::VWF::Display->new() reads a configuration file.  Give it its own,
	# rather than whatever happens to be in ~/lib/conf on this machine.  It
	# carries the reCAPTCHA settings the page reads from its config handle.
	my $config_dir = tempdir(CLEANUP => 1);
	open(my $fout, '>', File::Spec->catfile($config_dir, 'default')) or die "$config_dir/default: $!";
	print $fout <<'EOF';
<?xml version="1.0"?>
<config>
	<memory_cache>
		<driver>Null</driver>
	</memory_cache>
	<recaptcha>
		<enabled>1</enabled>
		<site_key>test_key</site_key>
		<secret_key>test_secret</secret_key>
	</recaptcha>
</config>
EOF
	close $fout;
	local $ENV{'CONFIG_DIR'} = $config_dir;

	# The handles are real objects, as the ones page.fcgi builds are: CGI::Info
	# supplies the request, CGI::Lingua the language, and HTTP::VWF::Config the
	# site's settings - recaptcha() among them, which captcha.pm reads through
	# the handle it is given.
	CGI::Info->reset();
	my $info = CGI::Info->new();
	my $lingua = CGI::Lingua->new({ supported => ['en-gb'], language => 'en' });
	require HTTP::VWF::Config;
	my $config = HTTP::VWF::Config->new({ info => $info });

	my $display = HTTP::VWF::Display::captcha->new({
		info => $info,
		config => $config,
		lingua => $lingua,
	});
	
	ok($display, 'Display object created');
	isa_ok($display, 'HTTP::VWF::Display::captcha');
};

subtest 'Rate limit bypass logic' => sub {
	plan tests => 5;
	
	use CHI;
	my $cache = CHI->new(driver => 'Memory', datastore => {});
	
	my $ip = '1.2.3.4';
	my $script = 'test';
	
	# Set request count over soft limit
	$cache->set("$script:rate_limit:$ip", 150, '60s');
	my $count = $cache->get("$script:rate_limit:$ip");
	is($count, 150, 'Request count set to 150');
	
	# Simulate CAPTCHA bypass
	$cache->set("$script:captcha_bypass:$ip", 1, '300s');
	my $has_bypass = $cache->get("$script:captcha_bypass:$ip");
	ok($has_bypass, 'CAPTCHA bypass token set');
	
	# Reset counter after successful CAPTCHA
	$cache->set("$script:rate_limit:$ip", 0, '60s');
	$count = $cache->get("$script:rate_limit:$ip");
	is($count, 0, 'Counter reset after CAPTCHA success');
	
	# Verify bypass expires
	$cache->set("$script:captcha_bypass:$ip", 1, '1s');
	sleep(1.1);
	my $expired = $cache->get("$script:captcha_bypass:$ip");
	is($expired, undef, 'CAPTCHA bypass expires');
	
	# Verify different IPs have separate bypass tokens
	$cache->set("$script:captcha_bypass:5.6.7.8", 1, '300s');
	ok($cache->get("$script:captcha_bypass:5.6.7.8"), 'Different IP has separate bypass');
};

done_testing();
