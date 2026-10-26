# Generated from Makefile.PL using makefilepl2cpanfile

requires 'perl', '5.20.0';

requires 'CGI::ACL', '0.06';   # For deny_cloud
requires 'CGI::Carp';
requires 'CGI::IDS';   # Intrusion detection, used by Allow.pm and Display.pm
requires 'CGI::Info', '1.14';   # 1.14 for is_ai()
requires 'CGI::Lingua', '0.61';
requires 'CHI';
requires 'Carp';
requires 'Carp::Always';
requires 'Class::Simple';
requires 'Config::Abstraction';
requires 'Config::Auto';
requires 'Crypt::URandom';   # CSPRNG for CSRF tokens
requires 'DBD::CSV';
requires 'DBI';
requires 'Data::Dumper';
requires 'Data::Throttler';
requires 'Data::Validate::URI';
requires 'Database::Abstraction';
requires 'DateTime';
requires 'Digest::MD5';
requires 'Digest::SHA';
requires 'Error';
requires 'FCGI';
requires 'FCGI::Buffer';
requires 'File::HomeDir';
requires 'File::Slurp';   # Display/table.pm
requires 'File::Spec';
requires 'File::pfopen';
requires 'Filesys::Df';   # Display/meta_data.pm
requires 'HTML::SocialMedia';
requires 'HTTP::Date';   # page.fcgi, for the access log lines
requires 'HTTP::Status';
requires 'JSON::MaybeXS';
requires 'LWP::Simple::WithCache';
requires 'LWP::UserAgent';
requires 'Log::Abstraction';
requires 'Log::WarnDie', '0.09';
requires 'Module::Runtime';   # Safe dynamic loading; avoids string eval
requires 'Object::Configure';
requires 'Params::Get', '0.13';
requires 'Params::Validate::Strict';
requires 'Readonly';
requires 'Scalar::Util';
requires 'String::Random';
requires 'Sys::MemInfo';
requires 'Sys::Uptime';
requires 'System::Info';
requires 'Template';   # The rendering engine behind the .tmpl files
requires 'Template::Filters';
requires 'Template::Plugin::EnvHash';
requires 'Template::Plugin::JSON';
requires 'Template::Plugin::Math';
requires 'Text::xSV::Slurp';
requires 'Time::HiRes';
requires 'Time::Piece';
requires 'Timer::Simple';
requires 'Try::Tiny';
requires 'XML::LibXML';   # Allow.pm reads the DShield feed with it

on 'configure' => sub {
	requires 'ExtUtils::MakeMaker', '6.64';   # Minimum version for TEST_REQUIRES
};

on 'test' => sub {
	requires 'Test::DescribeMe';   # t/vwf-sync.t is an author test
	requires 'Test::MockObject';
	requires 'Test::Most';
};

on 'develop' => sub {
	requires 'Devel::Cover';
	requires 'Perl::Critic';
	requires 'Test::Pod';
	requires 'Test::Pod::Coverage';
};
