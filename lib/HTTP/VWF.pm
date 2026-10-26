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
read - C<Config::Abstraction> takes either, and so does C<Config::Auto>, which
is what L<HTTP::VWF::Display::table> still reads its configuration with.  A
site whose configuration is already written the old way does not have to be
converted.  Note that the snippet in the document is a description rather than
a file to copy: it writes C<root_dir /path> with a space but C<memory_cache:>
and C<disc_cache:> with colons, and a file mixing the two separators is liable
to have the explanations taken as the values, or to be refused outright as not
being in a format that can be read.

F<t/config-format.t> holds this: it writes each form in a temporary directory
and reads it back through each reader.

The document's own FIXME - "Configuration files should be in .../conf, not
.../lib/conf" - is honoured: a site's F<conf/> sits at the top of it, beside
F<cgi-bin/>.

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
