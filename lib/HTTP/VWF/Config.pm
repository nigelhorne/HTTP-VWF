package HTTP::VWF::Config;

# VWF is licensed under GPL2.0 for personal use only
# njh@bandsman.co.uk

# Usage is subject to licence terms.
# The licence terms of this software are as follows:
# Personal single user, single computer use: GPL2
# All other users (including Commercial, Charity, Educational, Government)
#	must apply in writing for a licence for use from Nigel Horne at the
#	above e-mail.

use warnings;
use strict;

use Carp ();
use Config::Abstraction ();
use CGI::Info ();
use Data::Dumper ();
use Error::Simple;
use File::Spec ();
use Params::Get 0.13 ();

=encoding utf-8

=head1 NAME

HTTP::VWF::Config - Site-independent configuration file for the Versatile Web Framework

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

# Where a hosting server keeps the configuration of the sites it serves: one
# directory per site, named after the site, so that F</usr/lib/vwf/example.com>
# holds F<example.com>'s.  A server that keeps them elsewhere says so in
# C<< HTTP::VWF->new(directory => '/some/where') >>, or with the C<directory>
# parameter below.
our $DEFAULT_DIRECTORY = '/usr/lib/vwf';

=head1 SUBROUTINES/METHODS

=head2 new

Creates a new HTTP::VWF::Config instance with hierarchical configuration loading.

Takes these optional arguments:
	info (CGI::Info object)
	logger
	config_directory - used when the configuration directory can't be worked out
	config_file - name of the configuration file - otherwise determined dynamically
	config (ref to hash of values to override in the config file
	directory - where the server keeps the configuration of the sites it serves,
		one directory per site, F</usr/lib/vwf> unless told otherwise

Values in the file are overridden by what's in the environment

B<Parameters:>

=over 4

=item * C<info> - CGI::Info object (optional, created if not provided)

=item * C<logger> - Logger object with debug() method (optional)

=item * C<config_directory> - Additional config directory path (optional)

=item * C<config_file> - Specific config filename (optional)

=item * C<config> - Hash ref of override values (optional)

=item * C<directory> - The directory the server keeps the configuration of its
sites in, one directory per site, named after the site (optional, default
F</usr/lib/vwf>)

=back

B<Configuration Resolution Order:>
1. Base configuration files
2. Values from config parameter
3. Environment variable overrides

B<Directory Search Order:>
1. $ENV{CONFIG_DIR} (if set)
2. Provided config_directory
3. ../conf relative to script
4. ../../conf relative to script
5. $DOCUMENT_ROOT/../lib/conf
6. $HOME/lib/conf
7. $directory/$sitename - the server's own directory for this site

An entry earlier in that list overrides every entry after it, so a setting in
the site's own F<conf/>, beside F<cgi-bin/>, is not overridden by a leftover copy
in one of the F<lib/conf> directories that predate it, nor by one the server
keeps for the site.

B<The server's directory for a site.>  A host serving many sites cannot keep
them all in one F<conf/>: each site has a configuration of its own, and none of
them owns the server's.  C<directory> is the root they live under -
F</usr/lib/vwf> unless given - and C<$sitename> is the site's name, the domain
the request was made under, so F</usr/lib/vwf/example.com> is C<example.com>'s.
Inside it the same file names are looked for as in every other directory.  A
F<Host> header carrying a port contributes the bare domain: F<example.com:8080>
is looked up under F<example.com>.

The name comes from the request, so it is used only when it is a plain name: a
C<Host> of F<../../etc> contributes no directory at all, rather than one outside
the root.  A server that has not written a site's configuration yet is not an
error - there is simply nothing to read there, as with any other directory in the
search.

A F<Host> header that carries a port makes the domain name F<example.com:443>,
and the file for the bare domain is read underneath the port-specific one, so a
site does not need a copy of its configuration for each port it is reached on.

A host with no configuration file at all - a vhost whose file has not been
written yet, or a command line test - is not an error: the defaults are used,
and the file can be added later.  A file that is there and cannot be read is
still an error.

B<Returns:> Blessed HTTP::VWF::Config object

B<Throws:> Error::Simple on configuration errors

=head3 FORMAL SPECIFICATION

    [STRING, HASH, LOGGER]

    ConfigState ::= ⟨⟨ config_dirs : ℙ STRING;
                      config_data : HASH;
                      logger : LOGGER ⟩⟩

    ConfigArgs ::= ⟨⟨ info : CGI_Info;
                     logger : LOGGER;
                     config_directory : STRING;
                     config_file : STRING;
                     directory : STRING;
                     config : HASH ⟩⟩

    Init : ConfigArgs → ConfigState

    ∀ params : ConfigArgs •
      let dirs == if env.CONFIG_DIR ≠ ∅
                  then {env.CONFIG_DIR}
                  else default_dirs ∪ {params.config_directory} fi •
      let valid_dirs == {d : dirs | ∃ f : FILE • readable(d, f)} •
      valid_dirs ≠ ∅ ∧
      config_data ∈ HASH ∧
      config_data = merge(file_config, params.config, env_overrides)

    ValidConfigKey == {k : STRING | k ∈ dom config_data}

    GetConfigValue : ValidConfigKey → (STRING ∪ HASH ∪ ARRAY)

=cut

sub new
{
	my $proto = shift;
	my $params = Params::Get::get_params(undef, @_);

	if (exists $params->{logger} && defined $params->{logger}) {
		throw Error::Simple('logger must be an object with debug method')
		    unless ref($params->{logger}) && $params->{logger}->can('debug');
	}

	if($params->{'logger'}) {
		$params->{'logger'}->debug(__PACKAGE__, '->new()');
	}

	if(exists $params->{config} && defined $params->{config}) {
		throw Error::Simple('config must be a hash reference') unless ref($params->{config}) eq 'HASH';
	}

	my $class = ref($proto) || $proto;
	my $info = $params->{info} || CGI::Info->new();

	# The root the server keeps its per-site configuration directories under.
	# A directory that is not there contributes no files, like the other
	# built-in locations, so a server that has not created it yet is not an
	# error: there is simply nothing to read from it.
	my $directory = $params->{'directory'};
	throw Error::Simple('directory must be a string') if(defined($directory) && ref($directory));
	$directory = $DEFAULT_DIRECTORY if(!defined($directory) || ($directory eq ''));

	my @config_dirs;
	if($ENV{'CONFIG_DIR'}) {
		# Validate directory exists
		throw Error::Simple("CONFIG_DIR '$ENV{CONFIG_DIR}' does not exist or is not readable")
			unless -d $ENV{'CONFIG_DIR'} && -r $ENV{'CONFIG_DIR'};
		@config_dirs = ($ENV{'CONFIG_DIR'});
	} else {
		# Build the standard search path, most specific first, as documented at
		# the top of this file.  Config::Abstraction merges the directories in
		# the order it is given them, each one overriding the one before it, so
		# this list is reversed below before it is handed over: a search order is
		# the opposite of a merge order.  The reversal is of the *directories*,
		# and it happens before the per-directory variants are added below, or a
		# language directory would end up under the unlocalised one it is meant
		# to override.
		@config_dirs = ();

		# The caller's own directory takes precedence over every built-in one
		if($params->{config_directory}) {
			throw Error::Simple("config_directory must be a string") if ref($params->{config_directory});
			throw Error::Simple("config_directory '$params->{config_directory}' does not exist")
				unless -d $params->{config_directory};
			push(@config_dirs, $params->{config_directory});
		}

		# Then the site's own conf/, beside cgi-bin/ - the directory page.fcgi
		# reads - before the lib/conf directories that predate it.
		push(@config_dirs, File::Spec->catdir(
			$info->script_dir(),
			File::Spec->updir(),
			'conf'
		));
		push(@config_dirs, File::Spec->catdir(
			$info->script_dir(),
			File::Spec->updir(),
			File::Spec->updir(),
			'conf'
		));

		if($ENV{'DOCUMENT_ROOT'}) {
			push(@config_dirs, File::Spec->catdir(
				$ENV{'DOCUMENT_ROOT'},
				File::Spec->updir(),
				'lib',
				'conf'
			))
		}
		if($ENV{'HOME'}) {
			push(@config_dirs, File::Spec->catdir(
				$ENV{'HOME'},
				'lib',
				'conf'
			));
		}

		# Then the server's own directory for this site: a host serving many
		# sites keeps one configuration directory per site, named after the site,
		# under $directory.
		if(my $server_dir = $class->site_directory(directory => $directory, sitename => $info->domain_name())) {
			push(@config_dirs, $server_dir);
		}

		@config_dirs = reverse @config_dirs;
	}

	# Look for localised configurations
	my $language;
	if(my $lingua = $params->{'lingua'}) {
		$language = $lingua->language_code_alpha2();
	}
	$language ||= $info->lang();

	if($language) {
		@config_dirs = map {
			($_, "$_/default", "$_/$language")
		} @config_dirs;
	} else {
		@config_dirs = map {
			($_, File::Spec->catdir($_, 'default'))
		} @config_dirs;
	}

	if($params->{'debug'}) {
		if($params->{logger}) {
			while(my ($key,$value) = each %ENV) {
				if($value) {
					$params->{logger}->debug("$key=$value");
				}
			}
		}
	}

	# Config::Abstraction returns nothing, rather than an object, when there is
	# no file to read at all: a vhost that has not been given a config file yet,
	# the command line test in the POD, or CI, where the hostname is a container
	# id.  That is not a configuration error - the framework carries on with its
	# defaults, and with the values in $params->{config} on top of them - so only
	# a failure to read a file that is there is thrown.
	my $config;
	eval {
		my $config_abstraction = Config::Abstraction->new(
			config_dirs => \@config_dirs,
			config_files => [$class->config_file_names(
				domain => $info->domain_name(),
				extra => [$ENV{'CONFIG_FILE'}, $params->{'config_file'}],
			)],
			logger => $params->{'logger'}
		);
		$config = $config_abstraction ? $config_abstraction->all() : {};
		1;
	};
	if($@) {
		throw Error::Simple("Configuration error: $@");
	}
	$config ||= {};

	# Validate essential configuration structure
	throw Error::Simple('Configuration must be a hash reference') unless(ref($config) eq 'HASH');

	# The values in config are defaults which can be overridden by
	# the values in params->{config}
	if(defined($params->{'config'})) {
		$config = { %{$config}, %{$params->{'config'}} };
	}

	# Allow variables to be overridden by the environment
	foreach my $key(keys %{$config}) {
		if(my $value = $ENV{$key}) {
			# Validate environment variable names
			# throw Error::Simple("Invalid environment variable name: $key")
				# unless $key =~ /^[A-Z_][A-Z0-9_]*$/;

			# Sanitize values
			# $value =~ s/[^\w\s=\.\-]//g;	# Remove potentially dangerous characters

			if($params->{'logger'}) {
				$params->{'logger'}->debug(__PACKAGE__, ': ', __LINE__, " overwriting $key, ", $config->{$key}, " with $value");
			}
			# If the value contains an equals make it into a hash value
			if($value =~ /(.+)=(.+)/) {
				delete $config->{$key} if(!ref($config->{$key}));
				$config->{$key}{$1} = $2;
			} else {
				$config->{$key} = $value;
			}
		}
	}

	# Config::Any turns fields with spaces into arrays, put them back
	foreach my $field('Contents', 'SiteTitle') {
		next if(!exists $config->{$field});
		my $value = $config->{$field};

		if(ref($value) eq 'ARRAY') {
			$config->{$field} = join(' ', @{$value});
		}
	}

	# unless($config->{'config_path'}) {
		# $config->{'config_path'} = File::Spec->catdir($config_dir, $info->domain_name());
	# }
	if($params->{'debug'} && $params->{'logger'}) {
		$params->{'logger'}->debug(__PACKAGE__, '(', __LINE__, '): ', Data::Dumper->new([$config])->Dump());
	}

	return bless $config, $class;
}

=head2 site_directory

Purpose: the directory a server keeps this site's configuration in, which is
C<$directory> and the site's name - F</usr/lib/vwf/example.com>.

Takes the root and the name:
	directory - the server's root, defaulting to F</usr/lib/vwf>
	sitename - the site's name, as the request gives it, which may carry a port

Returns: the directory, or nothing when the name is not one a directory can be
made of.  The name arrives in the request's F<Host> header, so nothing that could
step out of the root - a slash, a colon that is not a port, a F<..> - is used:
a server that has not been given a configuration for a site is asked for no
directory rather than one somebody else has written.

=cut

sub site_directory
{
	shift;	# The class, which this does not need
	my %args = @_;

	my $sitename = $args{'sitename'};
	if(defined($sitename) && ($sitename =~ /\A(.+):\d+\z/)) {
		$sitename = $1;	# The site's own name, without a port on it
	}
	return undef unless(defined($sitename) && ($sitename =~ /\A[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?\z/) && (index($sitename, '..') < 0));

	my $directory = $args{'directory'};
	$directory = $DEFAULT_DIRECTORY if(!defined($directory) || ($directory eq ''));

	return File::Spec->catdir($directory, $sitename);
}

=head2 config_file_names

Purpose: the configuration files to read for a domain, most general first.

A F<Host> header may carry a port, and CGI::Info keeps it in the domain name -
F<example.com:443> - so that is the name the configuration is looked up under.
The port is not part of the site's identity, though, and a site keeps one file per
name, so the bare domain is read as well, underneath the port-specific file when
that exists.  Config::Abstraction merges the files in the order it is given
them, so the last name listed here is the one that wins.

Returns: a list of file names.

=cut

sub config_file_names
{
	shift;	# The class, which this does not need
	my %args = @_;

	my @files = ('default');

	my $domain = $args{'domain'};
	if(defined($domain) && ($domain =~ /^(.+):\d+$/)) {
		push(@files, $1);	# The site's own file, without the port on it
	}
	push(@files, $domain) if(defined($domain));

	# An explicitly named file is the caller's choice, so it comes last
	foreach my $name (@{ $args{'extra'} // [] }) {
		push(@files, $name) if(defined($name));
	}

	return @files;
}

sub AUTOLOAD
{
	our $AUTOLOAD;
	my $self = shift;

	return undef unless($self);
	return unless defined($AUTOLOAD);

	# Extract the key name from the AUTOLOAD variable
	(my $key = $AUTOLOAD) =~ s/.*:://;

	return unless defined($key);

	# Don't handle special methods
	return if $key eq 'DESTROY';

	# Validate method name - only allow safe config keys
	Carp::croak(__PACKAGE__, ": Invalid key name: $key") unless $key =~ /^[a-zA-Z_][a-zA-Z0-9_]*$/;

	# Return the value of the corresponding hash key
	# Only return existing keys to avoid auto-vivification
	return exists $self->{$key} ? $self->{$key} : undef;
}

1;
