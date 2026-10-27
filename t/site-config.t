#!/usr/bin/env perl

# The site's own settings, the ones page.fcgi used to have written into it: the
# directory its databases are in, the data modules it loads, the languages it
# offers and the addresses it allows or trusts.  Each is read from the domain's
# configuration file, and each has a default - the value the script used to
# hardcode - so that a site which says nothing about it behaves as it did before.
#
# Two things are held here, and they are different things:
#
#   - what a list-valued setting is when it arrives.  config_list() is read out
#     of the script and called, because the shapes a configuration file can give
#     are the part most easily got wrong, and the differences between them are
#     not visible from the script's own use of it.  This is the same extraction
#     t/security_tests.t does for blacklisted(), and for the same reason.
#
#   - that the script asks for each setting by name and no longer decides any of
#     them itself.  The defaults are checked to be the values that used to be
#     written into it, since a default that drifted would be a silent change for
#     every site that says nothing.
#
# What this cannot check is that a setting read is a setting acted on - that the
# data module named is the one loaded, or that the address allowed is the one
# admitted.  That is what the configuration is for at run time, and it was
# checked by running the script: see the "Site Settings" section of HTTP::VWF's
# documentation.

use strict;
use warnings;

use FindBin qw($Bin);
use File::Spec;
use Test::Most;

use lib File::Spec->catfile($Bin, '..', 'lib');

my $page_fcgi = File::Spec->catfile($Bin, '..', 'cgi-bin', 'page.fcgi');

plan skip_all => "Cannot find page.fcgi at $page_fcgi" unless(-f $page_fcgi);

open(my $in, '<', $page_fcgi) or die "$page_fcgi: $!";
my $full_code = do { local $/; <$in> };
close($in);

# Read a sub out of the script, braces matched: page.fcgi is a script and cannot
# be loaded as a module, so this is how its own tests have always reached it.
sub extract_sub {
	my ($code, $name) = @_;

	my $start = index($code, "sub $name\n");
	return undef if($start < 0);

	my $depth = 0;
	my $seen = 0;
	for(my $i = $start; $i < length($code); $i++) {
		my $char = substr($code, $i, 1);
		if($char eq '{') {
			$depth++;
			$seen = 1;
		} elsif($char eq '}') {
			$depth--;
			return substr($code, $start, $i - $start + 1) if($seen && ($depth == 0));
		}
	}

	return undef;
}

# The whole body of a sub, which is its last line up to the closing brace.
sub extract_body {
	my ($code, $name) = @_;

	my $sub = extract_sub($code, $name);
	return undef unless(defined($sub));

	$sub =~ s/.*?\n//s;	# drop the "sub name" line itself
	return $sub;
}

my $config_list_code = extract_sub($full_code, 'config_list');

plan skip_all => 'Cannot extract config_list() from page.fcgi' unless($config_list_code);

{
	# load the extracted config_list() into a package of its own
	my $loaded = eval "package ExtractedSiteConfig;\n$config_list_code\n1;";
	plan skip_all => "The extracted config_list() does not compile: $@" unless($loaded);
}

# What a site that says nothing gets, as written in the script.
sub scalar_default {
	my ($name) = @_;

	my ($value) = $full_code =~ /Readonly\s+my\s+\$$name\s*=>\s*'([^']*)'/;
	return $value;
}

sub list_default {
	my ($name) = @_;

	my ($value) = $full_code =~ /Readonly\s+my\s+\@$name\s*=>\s*qw\(([^)]*)\)/;
	return $value;
}

subtest 'a setting the site does not mention' => sub {
	my $config = {};

	is_deeply([ExtractedSiteConfig::config_list($config, 'supported_languages', 'en-gb')], ['en-gb'],
		'the caller\'s default is returned');
	is_deeply([ExtractedSiteConfig::config_list($config, 'allow_ips')], [],
		'and an empty default when there is no default');
};

subtest 'the plain form of a configuration file: one string' => sub {
	is_deeply([ExtractedSiteConfig::config_list({ supported_languages => 'en-gb' }, 'supported_languages', 'x')],
		['en-gb'], 'a single value');
	is_deeply([ExtractedSiteConfig::config_list({ supported_languages => 'en-gb fr' }, 'supported_languages', 'x')],
		['en-gb', 'fr'], 'values separated by spaces');
	is_deeply([ExtractedSiteConfig::config_list({ supported_languages => 'en-gb,fr' }, 'supported_languages', 'x')],
		['en-gb', 'fr'], 'values separated by commas');
	is_deeply([ExtractedSiteConfig::config_list({ allow_ips => "127.0.0.1, 192.168.1.1\n10.0.0.1" }, 'allow_ips', 'x')],
		['127.0.0.1', '192.168.1.1', '10.0.0.1'], 'and a mixture of the two');
};

subtest 'the XML form: one child per value' => sub {
	# This is what Config::Abstraction gives for
	# <allow_ips><ip>a</ip><ip>b</ip></allow_ips>: a hash of the children.  It
	# loads the file twice and so repeats them, which is not the site's doing.
	my $config = { allow_ips => { ip => ['108.44.193.70', '127.0.0.1', '108.44.193.70', '127.0.0.1'] } };

	is_deeply([ExtractedSiteConfig::config_list($config, 'allow_ips', 'x')],
		['108.44.193.70', '127.0.0.1'], 'the values are taken and the repetition dropped');

	is_deeply([ExtractedSiteConfig::config_list({ allow_ips => { ip => '127.0.0.1' } }, 'allow_ips', 'x')],
		['127.0.0.1'], 'one child on its own is a list of one');
};

subtest 'an array, and the order and repetitions of it' => sub {
	is_deeply([ExtractedSiteConfig::config_list({ data_modules => ['A::B', 'C::D'] }, 'data_modules', 'x')],
		['A::B', 'C::D'], 'an array is taken as it stands');
	is_deeply([ExtractedSiteConfig::config_list({ supported_languages => 'fr en-gb fr' }, 'supported_languages', 'x')],
		['fr', 'en-gb'], 'the order written is kept and repetitions are not');
};

subtest 'a setting a site has deliberately left empty' => sub {
	is_deeply([ExtractedSiteConfig::config_list({ supported_languages => '' }, 'supported_languages', 'en-gb')],
		[], 'no values, rather than the default: the site said so');
	is_deeply([ExtractedSiteConfig::config_list({ supported_languages => [] }, 'supported_languages', 'en-gb')],
		[], 'and the same for an empty list');
};

subtest 'each setting is asked for by name' => sub {
	# The one setting that is not a list is read as a plain value
	like($full_code, qr/\$config->\{'database_dir'\}/, 'page.fcgi reads database_dir from the configuration');

	foreach my $key (qw(data_modules supported_languages allow_ips rate_limit_trusted_ips)) {
		like($full_code, qr/config_list\(\$config,\s*'$key'/,
			"page.fcgi reads $key from the configuration");
	}
};

subtest 'the defaults are the values the script used to hardcode' => sub {
	is(scalar_default('DEFAULT_DATABASE_DIR'), 'data', 'the databases were in data/, beside cgi-bin/');
	is(list_default('DEFAULT_DATA_MODULES'), 'HTTP::VWF::Data::index', 'index was the one data module loaded');
	is(list_default('DEFAULT_SUPPORTED_LANGUAGES'), 'en-gb', 'en-gb was the only language offered');
	is(list_default('DEFAULT_RATE_LIMIT_TRUSTED_IPS'), '127.0.0.1 192.168.1.1', 'these addresses were exempt from rate limiting');
	like(list_default('DEFAULT_ALLOW_IPS'), qr/\b108\.44\.193\.70\b/, 'this site\'s own address was allowed through the geo-block');
	like(list_default('DEFAULT_ALLOW_IPS'), qr/\b127\.0\.0\.1\b/, 'so was localhost');
};

subtest 'none of them is decided by the script any more' => sub {
	unlike($full_code, qr/supported\s*=>\s*\[\s*'en-gb'\s*\]/, 'the languages are not written into the script');
	unlike($full_code, qr/->allow_ip\('108\.44\.193\.70'\)/, 'nor are the allowed addresses');
	unlike($full_code, qr/^Readonly my \@rate_limit_trusted_ips/m, 'nor the rate-limit exemptions');
	unlike($full_code, qr/my \$index = HTTP::VWF::Data::index->new\(\)/, 'nor which data modules exist');
	unlike($full_code, qr/my \$database_dir = "\$script_dir\/\.\.\/data"/, 'nor where the databases are');
};

done_testing();
