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

use Carp;
use Config::Abstraction;
use CGI::Info;
use Data::Dumper;
use Error::Simple;
use File::Spec;
use Params::Get 0.13;

=encoding utf-8

=head1 NAME

HTTP::VWF::Config - Site-independent configuration file for the Versatile Web Framework

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SUBROUTINES/METHODS

=head2 new

Creates a new HTTP::VWF::Config instance with hierarchical configuration loading.

Takes four optional arguments:
	info (CGI::Info object)
	logger
	config_directory - used when the configuration directory can't be worked out
	config_file - name of the configuration file - otherwise determined dynamically
	config (ref to hash of values to override in the config file

Values in the file are overridden by what's in the environment

B<Parameters:>

=over 4

=item * C<info> - CGI::Info object (optional, created if not provided)

=item * C<logger> - Logger object with debug() method (optional)

=item * C<config_directory> - Additional config directory path (optional)

=item * C<config_file> - Specific config filename (optional)

=item * C<config> - Hash ref of override values (optional)

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

An entry earlier in that list overrides every entry after it, so a setting in
the site's own F<conf/>, beside F<cgi-bin/>, is not overridden by a leftover copy
in one of the F<lib/conf> directories that predate it.

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
