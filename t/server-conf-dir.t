#!/usr/bin/env perl

# The directory a server keeps the configuration of the sites it serves in: one
# directory per site, named after the site, F</usr/lib/vwf/example.com> by
# default.  A host serving many sites cannot keep them all in one F<conf/>, and
# none of those sites owns the server's, so the location is the server's to
# name - HTTP::VWF->new(directory => '/some/where') - and it is read below
# anything the site writes for itself.
#
# Everything here happens in temporary directories, and every location that
# would otherwise supply a setting - the site's own F<conf/>, C<$HOME>, the
# document root - is pointed at one, so nothing is read from the machine the
# test runs on.

use strict;
use warnings;

use FindBin qw($Bin);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::Most;

use lib File::Spec->catfile($Bin, '..', 'lib');

use HTTP::VWF;
use HTTP::VWF::Config;
use HTTP::VWF::Display;

{
	# HTTP::VWF::Config takes the domain and the script directory from CGI::Info,
	# which cannot work either out from a command line, so this stands in for it.
	package MockInfo;

	sub new {
		my ($class, %args) = @_;
		return bless { %args }, $class;
	}

	sub domain_name { return $_[0]->{domain_name}; }
	sub script_dir { return $_[0]->{script_dir}; }
	sub root_dir { return $_[0]->{root_dir}; }
	sub lang { return 'en'; }
}

my $DOMAIN = 'example.com';

# The setting each configuration holds, so that the one that was read is visible
# in the result.
my $SERVER_ROOT_DIR = '/srv/example.com';
my $SITE_ROOT_DIR = '/srv/site.example.com';
my $EXPLICIT_ROOT_DIR = '/srv/explicit.example.com';

# Write a configuration into $dir, as a file named after the site, and return it.
sub write_config {
	my ($dir, $content) = @_;

	make_path($dir) unless(-d $dir);

	my $file = File::Spec->catfile($dir, $DOMAIN);
	open(my $out, '>', $file) or die "$file: $!";
	print $out $content;
	close($out) or die "$file: $!";

	return $file;
}

my $XML = <<"CONFIG";
<?xml version="1.0"?>
<config>
\t<root_dir>$SERVER_ROOT_DIR</root_dir>
</config>
CONFIG

# The plain form, which a site's own conf/ holds.
sub plain_config {
	my $root_dir = shift;

	return "root_dir $root_dir\n";
}

# A CGI script directory of its own, with no conf/ anywhere near it, so that
# only the directory under test can supply a setting.
sub site_script_dir {
	my $cgi = File::Spec->catdir(tempdir(CLEANUP => 1), 'site', 'cgi-bin');
	make_path($cgi);

	return $cgi;
}

# Read the configuration the way a request does, with every other location empty.
sub read_config {
	my ($directory, $host, $script_dir) = @_;

	local $ENV{'HOME'} = tempdir(CLEANUP => 1);
	delete local $ENV{'DOCUMENT_ROOT'};
	delete local $ENV{'CONFIG_DIR'};
	delete local $ENV{'CONFIG_FILE'};
	delete local $ENV{'root_dir'};

	my $info = MockInfo->new(
		domain_name => $host,
		script_dir => $script_dir // site_script_dir(),
	);

	my %params = (info => $info, logger => undef);
	$params{'directory'} = $directory if(defined($directory));

	return eval { HTTP::VWF::Config->new(%params) };
}

subtest 'the server directory is /usr/lib/vwf unless it is given' => sub {
	is(HTTP::VWF->new()->directory(), '/usr/lib/vwf', 'the default');
	is(HTTP::VWF->new(directory => '/etc/vwf')->directory(), '/etc/vwf',
		'a directory of the server\'s choosing');
	is(HTTP::VWF->new({ directory => '/etc/vwf' })->directory(), '/etc/vwf',
		'the same, given as a hash reference');
	is(HTTP::VWF->new(directory => undef)->directory(), '/usr/lib/vwf',
		'an undefined directory means the default');
	is(HTTP::VWF->new()->directory(), $HTTP::VWF::Config::DEFAULT_DIRECTORY,
		'and the default is the one the configuration reads');
};

subtest "a site's configuration is read from the server's directory for it" => sub {
	my $directory = tempdir(CLEANUP => 1);
	write_config(File::Spec->catdir($directory, $DOMAIN), $XML);

	my $config = read_config($directory, $DOMAIN);

	is(ref($config), 'HTTP::VWF::Config', 'a configuration was read');
	is($config->{'root_dir'}, $SERVER_ROOT_DIR,
		"the site's file in $directory/$DOMAIN was used");
};

subtest 'the directory given to HTTP::VWF->new() is the one read' => sub {
	my $directory = tempdir(CLEANUP => 1);
	write_config(File::Spec->catdir($directory, $DOMAIN), $XML);

	local $ENV{'HOME'} = tempdir(CLEANUP => 1);
	delete local $ENV{'DOCUMENT_ROOT'};
	delete local $ENV{'CONFIG_DIR'};
	delete local $ENV{'CONFIG_FILE'};
	delete local $ENV{'root_dir'};

	my $vwf = HTTP::VWF->new(
		directory => $directory,
		info => MockInfo->new(domain_name => $DOMAIN, script_dir => site_script_dir()),
	);
	my $config = $vwf->config();

	is(ref($config), 'HTTP::VWF::Config', 'the front door built a configuration');
	is($config->{'root_dir'}, $SERVER_ROOT_DIR, "from that directory's file for the site");
	is($vwf->config(), $config, 'and it is built once');
};

subtest "the site's own conf/ is not overridden by the server's directory" => sub {
	my $directory = tempdir(CLEANUP => 1);
	my $script_dir = site_script_dir();

	write_config(File::Spec->catdir($directory, $DOMAIN), $XML);
	write_config(File::Spec->catdir($script_dir, File::Spec->updir(), 'conf'), plain_config($SITE_ROOT_DIR));

	is(read_config($directory, $DOMAIN, $script_dir)->{'root_dir'}, $SITE_ROOT_DIR,
		"the site's own conf/ was the one used");
};

subtest 'CONFIG_DIR overrides every location, the server directory included' => sub {
	my $directory = tempdir(CLEANUP => 1);
	write_config(File::Spec->catdir($directory, $DOMAIN), $XML);

	my $explicit = tempdir(CLEANUP => 1);
	my $file = write_config($explicit, plain_config($EXPLICIT_ROOT_DIR));

	local $ENV{'CONFIG_DIR'} = $explicit;
	delete local $ENV{'CONFIG_FILE'};

	my $config = HTTP::VWF::Config->new(
		info => MockInfo->new(domain_name => $DOMAIN, script_dir => site_script_dir()),
		directory => $directory,
	);

	is(ref($config), 'HTTP::VWF::Config', 'a configuration was read');
	is($config->{'root_dir'}, $EXPLICIT_ROOT_DIR, "CONFIG_DIR was the one used, not $file");
};

subtest 'a Host header carrying a port still finds the bare domain' => sub {
	my $directory = tempdir(CLEANUP => 1);
	write_config(File::Spec->catdir($directory, $DOMAIN), $XML);

	is(read_config($directory, "$DOMAIN:8080")->{'root_dir'}, $SERVER_ROOT_DIR,
		"$DOMAIN:8080 was looked up under $DOMAIN");
};

subtest 'the directory is built from the root and the site name' => sub {
	my $root = tempdir(CLEANUP => 1);

	is(HTTP::VWF::Config->site_directory(directory => $root, sitename => $DOMAIN),
		File::Spec->catdir($root, $DOMAIN), 'the site name becomes a directory under the root');
	is(HTTP::VWF::Config->site_directory(directory => $root, sitename => "$DOMAIN:8080"),
		File::Spec->catdir($root, $DOMAIN), 'a port is not part of it');
	is(HTTP::VWF::Config->site_directory(sitename => $DOMAIN),
		File::Spec->catdir($HTTP::VWF::Config::DEFAULT_DIRECTORY, $DOMAIN),
		'and the default root is used when none is given');
	is(HTTP::VWF::Config->site_directory(directory => $root, sitename => ''), undef,
		'no name, no directory');
};

# The page modules read the site's configuration for themselves, so they have to
# look where the page script did.  Before this, a site configured only from the
# server's directory rendered a 404.
subtest 'the page modules find the server\'s directory for the site' => sub {
	my $root = tempdir(CLEANUP => 1);
	my $site_dir = File::Spec->catdir($root, $DOMAIN);
	make_path($site_dir);

	local $ENV{'HOME'} = tempdir(CLEANUP => 1);
	delete local $ENV{'DOCUMENT_ROOT'};
	delete local $ENV{'CONFIG_DIR'};
	delete local $ENV{'root_dir'};

	my $info = MockInfo->new(domain_name => $DOMAIN, script_dir => site_script_dir());

	is(HTTP::VWF::Display::_find_config_dir({ server_directory => $root }, $info), $site_dir,
		'the page modules look in the server\'s directory for the site');
};

subtest 'a Host header cannot point the search out of the directory' => sub {
	SKIP: {
		skip 'a file name with a slash in it cannot be written on Windows', 4
			if($^O eq 'MSWin32');

		my $tmp = tempdir(CLEANUP => 1);
		my $directory = File::Spec->catdir($tmp, 'vwf');
		make_path($directory);

		# A configuration beside the root, where a name built from the request
		# could reach if the name were used as a path.
		write_config(File::Spec->catdir($tmp, 'outside'), $XML);

		foreach my $host ('../outside', '..%2Foutside', 'outside/..', '/etc', 'example.com/../../outside') {
			my $config = read_config($directory, $host);

			is(ref($config), 'HTTP::VWF::Config', "a Host of '$host' is still answered");
			is($config->{'root_dir'}, undef, "   and reads nothing: '$host' contributes no directory");
		}
	}
};

done_testing();
