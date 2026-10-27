#!/usr/bin/env perl

# The configuration formats HTTP::VWF accepts.
#
# VWF's README describes a configuration file written as plain "key value"
# lines, and its worked example is XML; F<conf/example.com> in this distribution
# is XML.  Config::Abstraction reads both, and it is now the only reader the
# framework uses, so a site whose configuration was written the old way does not
# have to be converted.  This test holds that: it writes each form and reads it
# back.
#
# It also holds where a table looks for its configuration: the site's own
# F<conf/>, beside F<cgi-bin/>, and then the F<lib/conf> directories that were
# the only place it used to look.
#
# Everything here happens in temporary directories, including the site's, so
# that nothing is read from the machine the test runs on.  The reader tests are
# given the directory to read rather than left to search; the table subtests go
# through the search, since that is what they are about.

use strict;
use warnings;

use FindBin qw($Bin);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::Most;

use lib File::Spec->catfile($Bin, '..', 'lib');

use Config::Abstraction;
use HTTP::VWF::Config;
use HTTP::VWF::Display::table;

{
	# Display::table takes the site's domain and script directory from CGI::Info,
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

# A site called example.com, as the README's example and the shipped example
# configuration both are.
my $DOMAIN = 'example.com';

# The plain form the README's configuration section shows, written with one
# separator throughout: root_dir takes a space, and so do the others here.
my $PLAIN_ROOT_DIR = '/srv/plain.example.com';
my $PLAIN = <<"EOF";
root_dir $PLAIN_ROOT_DIR
memory_cache /var/cache/example.com/memory
disc_cache /var/cache/example.com/disc
EOF

# The XML form, with the nesting the shipped conf/example.com uses.
my $XML_ROOT_DIR = '/srv/xml.example.com';
my $XML = <<"EOF";
<?xml version="1.0"?>
<config>
\t<memory_cache>
\t\t<driver>Null</driver>
\t</memory_cache>
\t<disc_cache>
\t\t<driver>Null</driver>
\t</disc_cache>
\t<root_dir>$XML_ROOT_DIR</root_dir>
</config>
EOF

# What the README's snippet actually contains: a space after root_dir, a colon
# after each cache, and an explanation after that.
my $MIXED = <<'EOF';
root_dir /srv/mixed.example.com
memory_cache: where short-term volatile information is stored
disc_cache: where long-term information is stored
EOF

# Write $content into a directory of its own as a file named after the site, the
# way a site's conf/ holds it, and return the directory and the file.
sub write_config {
	my ($content, $dir) = @_;

	$dir //= tempdir(CLEANUP => 1);
	make_path($dir) unless(-d $dir);

	my $file = File::Spec->catfile($dir, $DOMAIN);
	open(my $out, '>', $file) or die "$file: $!";
	print $out $content;
	close($out) or die "$file: $!";

	return ($dir, $file);
}

# The way page.fcgi reads it.
sub abstraction_config {
	my ($dir) = @_;

	my $config;
	eval {
		$config = Config::Abstraction->new(
			env_prefix => 'EXAMPLE_COM_',
			flatten => 0,
			config_file => $DOMAIN,
			config_dirs => [$dir],
		)->all();
	};

	return $config;
}

subtest 'the plain form, read by Config::Abstraction' => sub {
	my ($dir, $file) = write_config($PLAIN);
	my $config = abstraction_config($dir);

	is(ref($config), 'HASH', 'it was read at all');
	is($config->{root_dir}, $PLAIN_ROOT_DIR, 'root_dir is read');
	is($config->{memory_cache}, '/var/cache/example.com/memory', 'memory_cache is read');
	is($config->{disc_cache}, '/var/cache/example.com/disc', 'disc_cache is read');

	# Guard against passing for the wrong reason, by reading some other
	# configuration file it found by searching rather than the one written here.
	ok(scalar(grep { $_ eq $file } @{$config->{config_path} // []}),
		'it was read from the file written here');
};

subtest 'the XML form, read by Config::Abstraction' => sub {
	my ($dir, $file) = write_config($XML);
	my $config = abstraction_config($dir);

	is(ref($config), 'HASH', 'it was read at all');
	is($config->{root_dir}, $XML_ROOT_DIR, 'root_dir is read');
	is_deeply($config->{memory_cache}, { driver => 'Null' }, 'nested settings keep their shape');
	is_deeply($config->{disc_cache}, { driver => 'Null' }, 'and so does the other cache');
	ok(scalar(grep { $_ eq $file } @{$config->{config_path} // []}),
		'it was read from the file written here');
};

# Lay out a site the way one is installed: a cgi-bin directory for the page
# script, a conf/ beside it, and a root_dir holding the templates and the
# databases.  The table's own file is written under the last of those, so that
# finding it shows root_dir was understood rather than merely parsed.
sub make_site {
	my $site = tempdir(CLEANUP => 1);
	my $script_dir = File::Spec->catdir($site, 'cgi-bin');
	my $root_dir = File::Spec->catdir($site, 'srv');
	my $conf_dir = File::Spec->catdir($site, 'conf');
	my $table_dir = File::Spec->catdir($root_dir, 'databases', 'HTTP', 'VWF', 'Display');

	make_path($script_dir, $conf_dir, $table_dir);

	my $table_file = File::Spec->catfile($table_dir, 'table');
	open(my $data, '>', $table_file) or die "$table_file: $!";
	print $data "name!email\na!a\@example.com\n";
	close($data) or die "$table_file: $!";

	return {
		conf_dir => $conf_dir,
		script_dir => $script_dir,
		table_file => $table_file,
		# The plain form, with a root_dir that can be written to.
		config => "root_dir $root_dir\nmemory_cache /var/cache/example.com/memory\ndisc_cache /var/cache/example.com/disc\n",
	};
}

# What a site with this directory layout looks like to the framework.
sub mock_info {
	my ($site) = @_;

	return MockInfo->new(
		domain_name => $DOMAIN,
		script_dir => $site->{script_dir},
		root_dir => File::Spec->catdir($site->{script_dir}, File::Spec->updir()),
	);
}

# get_file_path() dies when the file its configuration points at is not there,
# which is how a wrong location gives itself away; a wrong one is reported here
# as undef rather than killing the test.
#
# $home is the HOME to look under, and the assignment is made in here rather
# than by the caller: a "local" set in a helper that has already returned is
# undone, which would leave the machine's own HOME - and its lib/conf - in play.
# Anyway the tests below each say what should be found; this makes sure that
# nothing else can be what was found instead.
sub table_file_found {
	my ($site, $home) = @_;

	local $ENV{'HOME'} = $home if(defined($home));
	delete local $ENV{'DOCUMENT_ROOT'};
	delete local $ENV{'CONFIG_DIR'};
	delete local $ENV{'CONFIG_FILE'};
	# The environment overrides every setting a configuration file holds, and
	# these subtests are about which file the settings were read from.
	delete local $ENV{'root_dir'};

	my $table = HTTP::VWF::Display::table->new(info => mock_info($site));
	return eval { $table->get_file_path() };
}

subtest "Display::table reads the site's own conf/" => sub {
	my $site = make_site();
	write_config($site->{config}, $site->{conf_dir});

	# A HOME with nothing of the site's in it.
	is(table_file_found($site, tempdir(CLEANUP => 1)), $site->{table_file},
		"root_dir came from the site's conf/");
};

subtest 'Display::table still reads a configuration in HOME/lib/conf' => sub {
	my $site = make_site();
	my $home = tempdir(CLEANUP => 1);
	write_config($site->{config}, File::Spec->catdir($home, 'lib', 'conf'));

	is(table_file_found($site, $home), $site->{table_file},
		'the location it used to look in still works');
};

subtest "the site's conf/ is read before HOME/lib/conf" => sub {
	my $site = make_site();
	my $home = tempdir(CLEANUP => 1);

	# A stale copy left where the old location was, pointing elsewhere: a site
	# should not be at the mercy of a file it no longer writes.
	write_config('root_dir ' . tempdir(CLEANUP => 1) . "\n", File::Spec->catdir($home, 'lib', 'conf'));
	write_config($site->{config}, $site->{conf_dir});

	is(table_file_found($site, $home), $site->{table_file},
		"the site's own conf/ was the one used");
};

# Read through HTTP::VWF::Config itself, with the site's directory given and the
# domain supplied the way a Host header supplies it.
sub vwf_config {
	my ($dir, $host) = @_;

	# The environment overrides every setting the configuration file holds, so
	# an inherited root_dir would be read instead of the file's.
	local $ENV{'CONFIG_DIR'} = $dir;
	delete local $ENV{'CONFIG_FILE'};
	delete local $ENV{'root_dir'};

	my $info = MockInfo->new(domain_name => $host, script_dir => $dir);
	my $config = eval { HTTP::VWF::Config->new(info => $info) };

	return $config;
}

subtest 'a Host header with a port reads the domain file' => sub {
	my ($dir) = write_config($XML);	# Kept as F<example.com>, with no port on it

	my $config = vwf_config($dir, "$DOMAIN:443");
	is(ref($config), 'HTTP::VWF::Config', 'the configuration was read at all');
	is($config->{root_dir}, $XML_ROOT_DIR, "the bare domain's file was used");
};

subtest 'a file named after the port wins when there is one' => sub {
	SKIP: {
		# A port-specific file name holds a colon, which Windows does not allow
		skip 'a colon cannot appear in a file name on Windows', 3 if($^O eq 'MSWin32');

		my ($dir) = write_config($XML);	# The bare domain
		my $port_file = File::Spec->catfile($dir, "$DOMAIN:443");
		open(my $out, '>', $port_file) or die "$port_file: $!";
		print $out "<?xml version=\"1.0\"?>\n<config>\n\t<root_dir>/srv/port.example.com</root_dir>\n</config>\n";
		close($out) or die "$port_file: $!";

		my $port = vwf_config($dir, "$DOMAIN:443");
		is(ref($port), 'HTTP::VWF::Config', 'the configuration was read at all');
		is($port->{root_dir}, '/srv/port.example.com', 'the port-specific file was used');

		my $plain = vwf_config($dir, $DOMAIN);
		is($plain->{root_dir}, $XML_ROOT_DIR, 'and the bare domain still reads its own file');
	}
};

subtest 'a host with no configuration file at all gets the defaults' => sub {
	# A vhost whose file has not been written yet, the command line test in the
	# POD, or CI, where the hostname is a container id: there is nothing to read.
	# Config::Abstraction returns no object at all there, which is not a
	# configuration error - dying over it would take the site down for a file
	# that only describes it - so an empty configuration is built instead.
	my $dir = tempdir(CLEANUP => 1);	# Empty: no file of any name to read

	# HOME/lib/conf is searched too, so it must not be the machine's own: the
	# configuration has to be empty for the right reason, not because the test
	# happened to be run on a machine where the domain has no file either way.
	local $ENV{'HOME'} = tempdir(CLEANUP => 1);

	my $empty = vwf_config($dir, $DOMAIN);
	is(ref($empty), 'HTTP::VWF::Config', 'a configuration is still built');

	# The values the caller passes are applied on top of the defaults, so a
	# caller that supplies its own settings still gets them.
	local $ENV{'CONFIG_DIR'} = $dir;
	delete local $ENV{'CONFIG_FILE'};
	delete local $ENV{'root_dir'};
	my $info = MockInfo->new(domain_name => $DOMAIN, script_dir => $dir);
	my $overridden = eval {
		HTTP::VWF::Config->new(info => $info, config => { root_dir => '/srv/none.example.com' })
	};
	is($overridden->{'root_dir'}, '/srv/none.example.com', 'and the values passed in are used');
};

subtest "the README's snippet, which mixes the two separators" => sub {
	# It writes root_dir with a space and both caches with colons, so it is a
	# description rather than a file to copy: it is not taken as the plain form.
	# If that ever changes, the note warning about it in lib/HTTP/VWF.pm needs
	# revisiting.
	my ($dir) = write_config($MIXED);

	my $abstraction = abstraction_config($dir);
	ok(!(ref($abstraction) eq 'HASH' && defined $abstraction->{root_dir}),
		'Config::Abstraction does not read root_dir from it');
};

done_testing();
