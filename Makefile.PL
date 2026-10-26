use strict;
use warnings;
use ExtUtils::MakeMaker 6.64;	# 6.64 for TEST_REQUIRES

my $dist = {
	COMPRESS => 'gzip -9f',
	SUFFIX => 'gz'
};

if($^O eq 'darwin') {
	$dist->{'TAR'} = 'gtar';
}

WriteMakefile(
	NAME		=> 'HTTP::VWF',
	AUTHOR		=> q{Nigel Horne <njh@nigelhorne.com>},
	VERSION_FROM	=> 'lib/HTTP/VWF.pm',
	ABSTRACT_FROM	=> 'lib/HTTP/VWF.pm',
	((defined($ExtUtils::MakeMaker::VERSION) &&
	 ($ExtUtils::MakeMaker::VERSION >= 6.3002))
		? ('LICENSE'=> 'GPL')
		: ()),
	CONFIGURE_REQUIRES => {
		'ExtUtils::MakeMaker' => 6.64,	# Minimum version for TEST_REQUIRES
	}, TEST_REQUIRES => {
		'Test::MockObject' => 0,
		'Test::Most' => 0,
	}, PREREQ_PM => {
		'Carp' => 0,
		'Carp::Always' => 0,
		'CGI::ACL' => 0.06,		# For deny_cloud
		'CGI::Carp' => 0,
		'CGI::IDS' => 0,		# Intrusion detection, used by Allow.pm and Display.pm
		'CGI::Info' => 1.14,		# 1.14 for is_ai()
		'CGI::Lingua' => 0.61,
		'CHI' => 0,
		'Class::Simple' => 0,
		'Config::Abstraction' => 0,
		'Config::Auto' => 0,
		'Crypt::URandom' => 0,		# CSPRNG for CSRF tokens
		'Data::Throttler' => 0,
		'Data::Validate::URI' => 0,
		'Database::Abstraction' => 0,
		'Data::Dumper' => 0,
		'DateTime' => 0,
		'DBD::CSV' => 0,
		'DBI' => 0,
		'Digest::MD5' => 0,
		'Digest::SHA' => 0,
		'Error' => 0,
		'FCGI' => 0,
		'FCGI::Buffer' => 0,
		'File::HomeDir' => 0,
		'File::pfopen' => 0,
		'File::Slurp' => 0,		# Display/table.pm
		'File::Spec' => 0,
		'Filesys::Df' => 0,		# Display/meta_data.pm
		'HTML::SocialMedia' => 0,
		'HTTP::Date' => 0,		# page.fcgi, for the access log lines
		'HTTP::Status' => 0,
		'JSON::MaybeXS' => 0,
		'Log::Abstraction' => 0,
		'Log::WarnDie' => 0.09,
		'LWP::Simple::WithCache' => 0,
		'LWP::UserAgent' => 0,
		'Module::Runtime' => 0,		# Safe dynamic loading; avoids string eval
		'Object::Configure' => 0,
		'Params::Get' => 0.13,
		'Params::Validate::Strict' => 0,
		'Readonly' => 0,
		'Scalar::Util' => 0,
		'String::Random' => 0,
		'Sys::MemInfo' => 0,
		'Sys::Uptime' => 0,
		'System::Info' => 0,
		'Template' => 0,		# The rendering engine behind the .tmpl files
		'Template::Filters' => 0,
		'Template::Plugin::EnvHash' => 0,
		'Template::Plugin::JSON' => 0,
		'Template::Plugin::Math' => 0,
		'Text::xSV::Slurp' => 0,
		'Time::HiRes' => 0,
		'Time::Piece' => 0,
		'Timer::Simple' => 0,
		'Try::Tiny' => 0,
		'XML::LibXML' => 0,		# Allow.pm reads the DShield feed with it
	}, dist => $dist,
	clean => { FILES => 'HTTP-VWF-*' },
	META_MERGE => {
		'meta-spec' => { version => 2 },
		resources => {
			repository => {
				type => 'git',
				url => 'git://github.com/nigelhorne/HTTP-VWF.git',
				web => 'https://github.com/nigelhorne/HTTP-VWF',
			}, bugtracker => {
				web => 'https://github.com/nigelhorne/HTTP-VWF/issues',
				url => 'https://github.com/nigelhorne/HTTP-VWF/issues',
			}
		},
	},
	MIN_PERL_VERSION => '5.20.0',	# For `use feature qw(signatures)`
);
