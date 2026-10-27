package HTTP::VWF;

# HTTP::VWF is licensed under GPL2.0 for personal use only
# njh@nigelhorne.com

=encoding utf-8

=head1 NAME

HTTP::VWF - VWF (Versatile Web Framework) as a distributable package

=head1 SYNOPSIS

A site puts a page script in its own cgi-bin, and a directory of templates
beside it:

    #!/usr/bin/env perl
    # cgi-bin/page.fcgi

    use HTTP::VWF::Config;
    use HTTP::VWF::Allow;
    use HTTP::VWF::Utils;

    use HTTP::VWF::Display::index;
    use HTTP::VWF::Display::meta_data;

and then

    LANG=en_GB root_dir=/usr/lib/example.com ./page.fcgi page=index

=cut

our $VERSION = '0.01';

=head1 DESCRIPTION

HTTP::VWF is L<VWF|https://github.com/nigelhorne/vwf>, the Versatile Web
Framework, packaged as a CPAN distribution.  It is an MVC framework for
building responsive websites that adapt to the client's language, to the kind
of client (web, mobile, robot, search engine or AI crawler) and to whichever
database back end the site uses.

This module is the distribution's front door: it holds the version number and
this overview.  There is no class here to use.  Working the framework does
these modules:

=over 4

=item L<HTTP::VWF::Display>

The page renderer.  Given the configuration, the browser's language and the
kind of client it is, it finds the right template for a page and renders it.
A site subclasses it for each of its pages.

=item L<HTTP::VWF::Config>

Reads the site's XML configuration.

=item L<HTTP::VWF::Allow>

Access control and rate limiting.

=item L<HTTP::VWF::Blacklist>

The country blacklist, shared by the page script, L<HTTP::VWF::Allow> and
L<HTTP::VWF::Display>.

=item L<HTTP::VWF::Utils>

Cache initialisation and the Haversine distance calculation.

=item L<HTTP::VWF::CAPTCHA>

reCAPTCHA integration and the bypass that follows a solved challenge.

=item L<HTTP::VWF::Data::E<lt>sourceE<gt>>

The data access layer: CSV, XML and SQLite, through Database::Abstraction.

=back

C<cgi-bin/page.fcgi> in this distribution is a working page script to copy and
adapt into a site's own C<cgi-bin>; C<templates/>, C<conf/example.com> and
C<data/> beside it are the small site it serves, and the starting point for a
new one.  A site's templates sit under a path built from the page's class name,
so the file to change when the page module is C<HTTP::VWF::Display::index> is
F<templates/en/web/HTTP/VWF/Display/index.tmpl> - see L<HTTP::VWF::Display>
for the rest of the search order.  F<CLAUDE.md> records how a request is handled
once it arrives.

A site that used to carry a renamed copy of VWF of its own deletes that copy,
installs this distribution, renames C<VWF::> to C<HTTP::VWF::> in its own code,
and moves its templates from C<.../VWF/Display/> to C<.../HTTP/VWF/Display/>.

=head1 Keeping in step with VWF

The modules here are VWF's own, renamed from C<VWF::> to C<HTTP::VWF::> and
otherwise unchanged, so that a fix belongs in both.  VWF's development tree,
complete with its own demo site, is at
L<https://github.com/nigelhorne/vwf>.

F<t/vwf-sync.t> is an author test that holds the two together.  It diffs each
module here against its counterpart in a VWF checkout beside this one, with the
namespace neutralised on both sides, and fails for anything this distribution
has that VWF has not - a fix made here and not given upstream, or an older
revision of a line VWF has since changed.  Lines VWF has and we have not are
reported as a diagnostic rather than a failure, since that is a re-sync waiting
to happen.  POD, blank lines and C<$VERSION> are ignored, which is what lets
the two differ by their version numbers and their documentation.

It skips unless C<AUTHOR_TESTING> is set, and skips again when no VWF checkout
is found through C<$VWF_HOME> or C<../vwf>, so it does not run in CI and a CPAN
install is unaffected.

=head1 Compatibility with VWF

VWF has a F<README> of its own, describing the framework in the terms its
author uses for it.  Read it beside this one: it is the framework's own
account of itself, and most of it is true of HTTP::VWF as it stands.

Parts of it were written against an earlier design, though, and it does not
always agree with the code it now ships with - in one place it does not agree
with itself.  What follows is the two of them mapped, so that a reader working
from the older document is not misled, and so that a difference is recorded
here rather than left to be discovered.  Where the two disagree, the code is
what runs.

=head2 What that documentation describes, that HTTP::VWF does

=over 4

=item One FastCGI script, with access control and caching

"The framework handles web requests using FastCGI", "the idea is to create
page.fcgi", and "access control (including rate limiting), and caching".
C<cgi-bin/page.fcgi> is that script; L<HTTP::VWF::Allow> is the access control
and rate limiting, and C<FCGI::Buffer> the caching.

=item The page that follows the browser

"the correct index.htm (or index.tmpl) file based on the browser language
setting (e.g. en-GB) and type (e.g. mobile)".  C<CGI::Lingua> gives the
language and region, and C<HTTP::VWF::Display::_types()> the kind of client.
"The fall back is web, so if a mobile browser visits and there is no specific
mobile page to display then the web page will be displayed" is exactly how it
behaves.

=item The file extensions

C<.tmpl> goes through the Template Toolkit, C<.html> and C<.htm> are sent as
they are, and C<.txt> is sent as it is with a C<Content-Type> of C<text/plain>.
All three behave as described.  C<.tt> is accepted as a second name for a
Template Toolkit file, and an HTML response says C<charset=UTF-8> as well.

=item C<root_dir>, and the configuration file named after the site

"The name of the configuration file the sitename, e.g.
/usr/lib/conf/example.com", and "root_dir /full/path/to/template directory".
F<conf/example.com> in this distribution is that file, and C<root_dir> is the
directory holding the site's F<templates/>, as described.

Both the plain form the document shows and the XML form the example uses are
read - C<Config::Abstraction> takes either, and it is the only reader the
framework uses.  A site whose configuration is already written the old way does
not have to be converted.
Note that the snippet in the document is a description rather than a file to
copy: it writes C<root_dir /path> with a space but C<memory_cache:> and
C<disc_cache:> with colons, and a file mixing the two separators is liable to
have the explanations taken as the values, or to be refused outright as not
being in a format that can be read.

F<t/config-format.t> holds this: it writes each form in a temporary directory
and reads it back.

The document's own FIXME - "Configuration files should be in .../conf, not
.../lib/conf" - is honoured: a site's F<conf/> sits at the top of the search
order, beside F<cgi-bin/>, and a setting in it is not overridden by a leftover
copy of the file in one of the F<lib/conf> directories that predate it.  That is
where C<page.fcgi> has always read the file, and L<HTTP::VWF::Display::table>
reads it from there too: it used to look only in F<~/lib/conf>, which left a
site declaring its C<root_dir> in F<conf/> and in F<~/lib/conf> both, and free to
have the two disagree.

=item Debugging from the command line

C<perl -c -Ilib cgi-bin/page.fcgi>, C<--mobile>, C<--search-engine>,
C<lang=fr>, C<key=value> and C<lint_content=0> all work as the document's
"Usage" section shows.  The C<--mobile> and C<--search-engine> flags are
CGI::Info's, read from C<@ARGV>, so they are available to any script that uses
it.

=item Data in the site's own directories

"Data stored in the files .../databases/ ... CSV, XML and SQLite format files
are supported."  There are two directories in play, and both are read.
L<HTTP::VWF::Display::table> reads F<root_dir/databases/>, which is the
F<.../databases/> the document names.  C<page.fcgi> separately opens the
directory beside it - F<data/>, next to its own F<cgi-bin/> - through
Database::Abstraction, and hands C<databasedir> to the template, which is what
serves CSV, XML and SQLite.

=item The F<save_to> caveat

"Every time you upload a new site ensure that you remove the save_to
directory, since that contains cached copies of pages that will be inconsistent
with the new site."  Still true, and still worth doing: C<page.fcgi> keeps a
day's worth of rendered pages under F<root_dir/save_to>.

=back

=head2 Where that documentation has moved on

=over 4

=item The shape of the template path

The document gives the hierarchy as
C<.../language/region/[web|mobile|robot|search]/filename.[html|tmpl|txt]>, and
four paragraphs later shows it the other way round, as
C<.../web/en/index.tmpl>.  The code searches both, the kind of client first:
for each kind, C<< <kind>/<language>/<region> >>, then
C<< <kind>/<language> >>, then C<< <language>/<kind> >>, then
C<< <kind>/default >>, then C<< default/<kind> >>, then C<< <kind> >> alone,
and finally the fall-back sequence C<web>, C<default/web>, C<default> and the
templates directory itself.

The filename is not the page's name either: the path ends with the page's own
class path, so C<HTTP::VWF::Display::index> is sought as
F<templates/en/web/HTTP/VWF/Display/index.tmpl>.  The worked example in the
document, F<templates/VWF/index.html>, is from before pages gained the
C<Display::> component, so it would now be
F<templates/HTTP/VWF/Display/index.html>.

C<ai> is a kind of client the document does not list: an AI crawler, which
C<CGI::Info::is_ai()> recognises and which falls back to the C<robot> and
C<search> templates before C<web>.  A search engine likewise falls back to
C<robot>, and a robot to C<search>.

=item One script, not one per page

"You'll need to create cgi-bin files for each of your page sets (e.g. create
foo.fcgi for .../web/*/*/foo.html) ... change the two places that VWF::index
appear to VWF::foo."  That was the design when it was written, and the
commented-out line that did it is still in C<page.fcgi>.  Now one C<page.fcgi>
serves every page: the page is named by the C<page> parameter, and only those
the configuration allows can be loaded.  A request that names no page at all is
answered with a 300 listing the pages that may be asked for.

=item Installing the framework

"copy the contents of the lib directory to /usr/lib/VMF (or a place of your
choice)" and "modify index.fcgi changing the 'use /usr/lib' directive"
describe installing the framework into a site by hand.  That step is what this
distribution replaces: HTTP::VWF is installed, and a site's C<use lib> line
only has to reach the site's own page subclasses, if it has any.

The C<lazy> step in the document's "Overview" is no longer needed either -
nothing here uses C<lazy>, and the dependencies are declared in F<Makefile.PL>
and F<cpanfile>.

=item The logging configuration

"Finally change conf/index.l4pconf to the logging mechanism of your choice."
Logging is configured in the domain configuration file now, in the
C<< <logger> >> section that Log::Abstraction reads, so this distribution ships
no F<l4pconf> file: nothing would read it.

=item The redirect

The F<.htaccess> the document shows redirects C</index.html> to
C</cgi-bin/index.fcgi>.  The script this distribution ships is
C<cgi-bin/page.fcgi>; the document uses both names for it.

=back

=head2 What changes for a site that uses this distribution

=over 4

=item Every C<VWF::> is C<HTTP::VWF::>

The document names C<VWF::Display>, C<VWF::Config>, C<VWF::Allow> and the rest,
and a page subclasses C<VWF::Display>.  Here they are C<HTTP::VWF::Display>,
C<HTTP::VWF::Config>, C<HTTP::VWF::Allow> and the rest, and a page writes
C<< use parent 'HTTP::VWF::Display' >>.

=item The template directory gains a level

Because the page's class path is part of the template path,
F<.../VWF/Display/> becomes F<.../HTTP/VWF/Display/>.

=back

=head1 Migrating a site from VWF

A site that used VWF before this distribution existed carries its own copy of
the modules on its C<@INC>, and a F<cgi-bin/page.fcgi> it has edited ever since.
Moving it over is a change of module names, of where the configuration lives,
and of which files the site still needs.  The steps can be taken one at a time,
each checked before the next is started.

=over 4

=item 1. Install this distribution, and stop carrying VWF

Remove the site's own copy of VWF from its C<@INC> - usually a F<lib/VWF/>
directory among its modules - and install this distribution in its place:

	cpanm HTTP::VWF

Modules the site owns keep their names: a C<BBPortal::Display::news> is not
VWF's, and does not move.

=item 2. Rename the framework's namespace in the site's code

Every C<VWF::> the site mentions becomes C<HTTP::VWF::>.  That is the C<use>
lines in its page script (C<VWF::Allow>, C<VWF::Config>, C<VWF::Utils>,
C<VWF::Data::vwf_log>, C<VWF::CAPTCHA>, C<VWF::Display::captcha> and the rest),
the C<use parent> of each of its own page classes, and any class name built as a
string - C<"VWF::Display::$page"> here is C<"HTTP::VWF::Display::$page">.

=item 3. Move the framework's templates down one level

The template path follows the class name, so F<templates/en/web/VWF/Display/>
becomes F<templates/en/web/HTTP/VWF/Display/>.  The site's own page classes are
unaffected: F<.../BBPortal/Display/> stays where it is.

=item 4. Put the configuration in the site's own F<conf/>

Move F<~/lib/conf/E<lt>domainE<gt>> - and anything under F</usr/lib/conf/>, the
location VWF's own README names - to F<conf/E<lt>domainE<gt>> beside
F<cgi-bin/>.  The file itself needs no editing: the plain C<key value> form the
README shows and the XML form its example uses are both read from either
location, by C<Config::Abstraction>.  F<conf/example.com> in this distribution
is an example to copy.

The site's F<conf/> is searched first, so a setting in it cannot be overridden
by an old copy left in F<~/lib/conf>.  Delete that copy anyway: VWF's own
C<VWF::Config> merges those directories the other way round, and where it is
still running a leftover file there wins.

Do not bring per-port copies across.  A request whose C<Host> header carries a
port, F<example.com:443>, is looked up under that name and then under
F<example.com> beneath it, so one file serves every port the site is reached on.

=item 5. Decide whether the site keeps its own page script

=over 4

=item * A site whose pages are all the framework's can take this distribution's
F<cgi-bin/page.fcgi> as it stands.  Its databases, data modules, languages and
addresses then come from the configuration file - see L</Site settings> - and it
need not be edited to keep the behaviour it had, since each default is the value
the old script carried.

=item * A site with pages of its own keeps its script, because that is what
loads them: C<BBPortal::Display::$page> is not something the shipped script
knows about.  Rename the namespaces as in step 2 and leave the rest as it is.
The settings in L</Site settings> reach a site only when its script asks for
them; the C<config_list()> helper that reads them lives in F<page.fcgi> rather
than in a module, so copy it, or read the configuration hash directly, if the
site wants them.

=back

=item 6. Check the prerequisites, and anything the site had of its own

Two modules are optional here although a VWF site may have installed them:
F<Filesys::Df> and F<XML::LibXML>, neither of which builds everywhere - see
L</Optional prerequisites>.  An existing throttle store carries over unchanged:
it is the same YAML file, named by C<throttle-E<gt>{file}>, with C<max_items>
and C<interval> as they were.  So does an access log named by C<vwflog>.

=item 7. Run the site before it is deployed

From the site's own F<cgi-bin>, the line the script's header gives:

	LANG=en_GB root_dir=$(pwd)/.. ./page.fcgi page=index

The web server's configuration does not change, unless the site named its script
F<index.fcgi> where this distribution names it F<page.fcgi>.

=item 8. Keep the two in step

A change made to one of the copied modules belongs in VWF as well.
F<t/vwf-sync.t> fails for anything here that VWF has not got, which is what
keeps the next site's migration a rename rather than a port - see
L</Keeping in step with VWF>.

=back

=head1 Site settings

A site describes itself in the configuration file named after its domain, in
its own F<conf/> beside F<cgi-bin/>.  These are the settings this
distribution's own F<cgi-bin/page.fcgi> reads; a site that adapts that script
reads the same ones.

Each has a default, and every default is the value that used to be written into
the script - so a site that says nothing about a setting behaves exactly as it
did before the setting existed.  F<t/site-config.t> holds the defaults in place,
so one cannot drift unnoticed.

=over 4

=item C<database_dir>

Where the site's databases are, as C<Database::Abstraction> reads them, and what
a page is given as C<databasedir>.  Default: F<data/>, beside F<cgi-bin/>.

=item C<data_modules>

The data modules the site loads.  Each is loaded, constructed with C<< ->new() >>
and given to every page under the last part of its name, lower-cased, so that a
site's C<Bands::Data::bands> arrives at the page as C<bands>.  Default:
C<HTTP::VWF::Data::index>, which is the handle L<HTTP::VWF::Display::index>
needs.  The access log is not one of these: C<page.fcgi> builds its reader
itself from the C<vwflog> setting, since it has to be told which log to read.

=item C<supported_languages>

The languages the site offers, for example C<en-gb fr>.  C<CGI::Lingua> negotiates
within this list, so a language's templates are only reachable once it is listed.
Default: C<en-gb>.

=item C<allow_ips>

Addresses allowed through the geo-block, passed to C<CGI::ACL>'s C<allow_ip()>.
An address here is still refused if its reverse DNS says it is in a cloud range,
and L<HTTP::VWF::Allow> has checks of its own that this does not bypass.  Default:
C<108.44.193.70> and C<127.0.0.1>, the first being one site's own address, kept so
that the sites this script came from keep working.  A site with an address of its
own should set this.

It is not called C<allowed_ips>, and cannot be: that is a C<CGI::ACL>
constructor argument, and C<CGI::ACL>'s C<new()> runs the site's configuration
through C<Object::Configure::configure()>, which would hand a key of that name to
it as a string where a hash is expected - breaking access control outright.

=item C<rate_limit_trusted_ips>

Addresses exempt from rate limiting.  Default: C<127.0.0.1> and C<192.168.1.1> -
loopback, and one private address.

=item C<throttle>

C<file> names the throttle store, C<max_items> is how many requests one address
may make in C<interval> seconds, and both default to the values the framework
has always used: a file called F<throttle> in the site's temporary directory,
and 30 requests per 90 seconds.  A store that cannot be used is reported at
error level and the request is served, rather than every visitor being refused
for a fault of the server - see L<HTTP::VWF::Throttle>, in particular "WHEN THE
STORE CANNOT BE USED".

=item C<pages>

The pages C<?page=> may load.  Without it, every C<Display/*.pm> shipped here may
be loaded except C<captcha>.  See L<HTTP::VWF::Display>.

=item C<blacklist_countries>

The countries refused access.  See L<HTTP::VWF::Blacklist>.

=item C<vwflog>

Where the access log is written, and read back by the meta-data page.  Default:
F<vwf.log> in the directory C<CGI::Info> reports as the log directory.

=back

A list-valued setting can be written as one string of values separated by commas
or spaces, or as an element with one child per value, so that an XML
configuration file can hold a list in whichever way reads better:

	<allow_ips>108.44.193.70, 127.0.0.1</allow_ips>

	<allow_ips>
		<ip>108.44.193.70</ip>
		<ip>127.0.0.1</ip>
	</allow_ips>

F<conf/example.com> carries each of these settings as a commented example.

=head1 Optional prerequisites

Two of the modules the framework can use are recommended rather than required,
because neither can be installed everywhere and a site works without them:

=over 4

=item C<Filesys::Df>

The disk usage figure on the meta-data page.  Its own F<Makefile.PL> refuses
Windows - it prints "This module does not support Windows" and points at
C<Filesys::DfPortable> - so this distribution does not declare it there at all.
Requiring it would make C<cpanm --installdeps> fail and HTTP::VWF impossible to
install on Windows.  Without it the meta-data page leaves the figure out.

=item C<XML::LibXML>

The parser L<HTTP::VWF::Allow> reads the DShield feed with.  It links against a
system C<libxml2>, which Strawberry Perl does not ship, so it does not build on
Windows either.  Without it L<HTTP::VWF::Allow> says once that it is skipping
the feed and carries on; the checks after that point in the module still run,
as they do when the feed cannot be downloaded.

=back

Everything else in F<Makefile.PL> is required on every platform.  Both of these
are loaded when they are first needed rather than with C<use>, so neither is
needed to install this distribution, and the test suite passes without them.

=head1 LICENSE

Licensed under GPL2.0 for personal use only.

=head1 AUTHOR

Nigel Horne, C<< <njh at nigelhorne.com> >>

=cut

1;
