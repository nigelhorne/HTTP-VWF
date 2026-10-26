#!/usr/bin/env perl

# The configuration formats HTTP::VWF accepts.
#
# VWF's README describes a configuration file written as plain "key value"
# lines, and its worked example is XML; F<conf/example.com> in this distribution
# is XML.  Both forms are read by both readers - Config::Abstraction, which
# page.fcgi builds its configuration with, and Config::Auto, which
# HTTP::VWF::Display::table still reads its own with - so that a site whose
# configuration was written the old way does not have to be converted.  This
# test holds that: it writes each form and reads it back through each reader.
#
# Everything here happens in a temporary directory.  Config::Abstraction is
# given the directory to read rather than left to search, and the one place that
# does need a home directory - Display::table - is given its own.

use strict;
use warnings;

use FindBin qw($Bin);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::Most;

use lib File::Spec->catfile($Bin, '..', 'lib');

use Config::Abstraction;
use Config::Auto;
use HTTP::VWF::Display::table;

{
	# Display::table takes the site's domain from CGI::Info, which cannot work
	# out a domain from a command line, so this stands in for it.
	package MockInfo;

	sub new {
		my ($class, $domain) = @_;
		return bless { domain => $domain }, $class;
	}

	sub domain_name { return $_[0]->{domain}; }
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

# The way HTTP::VWF::Display::table reads it.
sub auto_config {
	my ($dir) = @_;

	my $config;
	eval { $config = Config::Auto::parse($DOMAIN, path => $dir); };

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

subtest 'the plain form, read by Config::Auto' => sub {
	my ($dir) = write_config($PLAIN);
	my $config = auto_config($dir);

	is(ref($config), 'HASH', 'it was read at all');
	is($config->{root_dir}, $PLAIN_ROOT_DIR, 'root_dir is read');
	is($config->{memory_cache}, '/var/cache/example.com/memory', 'memory_cache is read');
	is($config->{disc_cache}, '/var/cache/example.com/disc', 'disc_cache is read');
};

subtest 'the XML form, read by Config::Auto' => sub {
	my ($dir) = write_config($XML);
	my $config = auto_config($dir);

	is(ref($config), 'HASH', 'it was read at all');
	is($config->{root_dir}, $XML_ROOT_DIR, 'root_dir is read');
	is_deeply($config->{memory_cache}, { driver => 'Null' }, 'nested settings keep their shape');
	is_deeply($config->{disc_cache}, { driver => 'Null' }, 'and so does the other cache');
};

# The point of the compatibility: whichever reader a part of the framework uses,
# the site sees the same settings.
subtest 'the two readers agree' => sub {
	foreach my $form (['plain', $PLAIN], ['XML', $XML]) {
		my ($name, $content) = @{$form};

		my ($dir) = write_config($content);
		my $abstraction = abstraction_config($dir);
		my $auto = auto_config($dir);

		# config_path is Config::Abstraction recording where it read from, not a
		# setting, so only the settings themselves are compared.
		foreach my $key (qw(root_dir memory_cache disc_cache)) {
			is_deeply($abstraction->{$key}, $auto->{$key}, "$name: both readers see $key the same");
		}
	}
};

subtest 'Display::table reads a configuration written the old way' => sub {
	# Display::table looks for its configuration through HOME/lib/conf, which is
	# where VWF's own FIXME says the files had ended up, so that is where this
	# one goes - not in the site's conf/ that page.fcgi reads.
	my $home = tempdir(CLEANUP => 1);
	my $root_dir = tempdir(CLEANUP => 1);
	my $conf_dir = File::Spec->catdir($home, 'lib', 'conf');
	make_path($conf_dir);

	# The same plain form, with a root_dir that can be written to.
	write_config("root_dir $root_dir\nmemory_cache /var/cache/example.com/memory\ndisc_cache /var/cache/example.com/disc\n", $conf_dir);

	local $ENV{'HOME'} = $home;
	delete local $ENV{'DOCUMENT_ROOT'};

	my $table = HTTP::VWF::Display::table->new(info => MockInfo->new($DOMAIN));

	# get_file_path() reads root_dir out of that configuration and looks for the
	# table's own file beneath it, so finding that file shows the settings were
	# understood rather than merely parsed.
	my $table_dir = File::Spec->catdir($root_dir, 'databases', 'HTTP', 'VWF', 'Display');
	make_path($table_dir);
	my $table_file = File::Spec->catfile($table_dir, 'table');
	open(my $data, '>', $table_file) or die "$table_file: $!";
	print $data "name!email\na!a\@example.com\n";
	close($data) or die "$table_file: $!";

	is($table->get_file_path(), $table_file, 'the old-way configuration led it to the table file');
};

subtest "the README's snippet, which mixes the two separators" => sub {
	# It writes root_dir with a space and both caches with colons, so it is a
	# description rather than a file to copy: neither reader takes it as the
	# plain form.  If either ever starts to, the note warning about it in
	# lib/HTTP/VWF.pm needs revisiting.
	my ($dir) = write_config($MIXED);

	my $abstraction = abstraction_config($dir);
	ok(!(ref($abstraction) eq 'HASH' && defined $abstraction->{root_dir}),
		'Config::Abstraction does not read root_dir from it');

	my $auto = auto_config($dir);
	ok(!(ref($auto) eq 'HASH' && defined $auto->{root_dir}),
		'Config::Auto does not read root_dir from it');
};

done_testing();
