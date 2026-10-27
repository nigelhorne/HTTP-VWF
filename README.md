## Name

HTTP::VWF - VWF (Versatile Web Framework) as a distributable package

## Synopsis

A site puts a page script in its own cgi-bin, and a directory of templates
beside it:

```perl
#!/usr/bin/env perl
# cgi-bin/page.fcgi

use HTTP::VWF::Config;
use HTTP::VWF::Allow;
use HTTP::VWF::Utils;

use HTTP::VWF::Display::index;
use HTTP::VWF::Display::meta_data;
```

and then

```
LANG=en_GB root_dir=/usr/lib/example.com ./page.fcgi page=index
```

## Description

HTTP::VWF is [VWF](https://github.com/nigelhorne/vwf), the Versatile Web
Framework, packaged as a CPAN distribution.  It is an MVC framework for
building responsive websites that adapt to the client's language, to the kind
of client (web, mobile, robot, search engine or AI crawler) and to whichever
database back end the site uses.

This module is the distribution's front door: it holds the version number and
this overview.  There is no class here to use.  Working the framework does
these modules:

- [HTTP::VWF::Display](https://metacpan.org/pod/HTTP%3A%3AVWF%3A%3ADisplay)

    The page renderer.  Given the configuration, the browser's language and the
    kind of client it is, it finds the right template for a page and renders it.
    A site subclasses it for each of its pages.

- [HTTP::VWF::Config](https://metacpan.org/pod/HTTP%3A%3AVWF%3A%3AConfig)

    Reads the site's XML configuration.

- [HTTP::VWF::Allow](https://metacpan.org/pod/HTTP%3A%3AVWF%3A%3AAllow)

    Access control and rate limiting.

- [HTTP::VWF::Blacklist](https://metacpan.org/pod/HTTP%3A%3AVWF%3A%3ABlacklist)

    The country blacklist, shared by the page script, [HTTP::VWF::Allow](https://metacpan.org/pod/HTTP%3A%3AVWF%3A%3AAllow) and
    [HTTP::VWF::Display](https://metacpan.org/pod/HTTP%3A%3AVWF%3A%3ADisplay).

- [HTTP::VWF::Utils](https://metacpan.org/pod/HTTP%3A%3AVWF%3A%3AUtils)

    Cache initialisation and the Haversine distance calculation.

- [HTTP::VWF::CAPTCHA](https://metacpan.org/pod/HTTP%3A%3AVWF%3A%3ACAPTCHA)

    reCAPTCHA integration and the bypass that follows a solved challenge.

- [HTTP::VWF::Data::&lt;source>](https://metacpan.org/pod/HTTP%3A%3AVWF%3A%3AData%3A%3A%3Csource%3E)

    The data access layer: CSV, XML and SQLite, through Database::Abstraction.

`cgi-bin/page.fcgi` in this distribution is a working page script to copy and
adapt into a site's own `cgi-bin`; `templates/`, `conf/example.com` and
`data/` beside it are the small site it serves, and the starting point for a
new one.  A site's templates sit under a path built from the page's class name,
so the file to change when the page module is `HTTP::VWF::Display::index` is
`templates/en/web/HTTP/VWF/Display/index.tmpl` - see [HTTP::VWF::Display](https://metacpan.org/pod/HTTP%3A%3AVWF%3A%3ADisplay)
for the rest of the search order.  `CLAUDE.md` records how a request is handled
once it arrives.

A site that used to carry a renamed copy of VWF of its own deletes that copy,
installs this distribution, renames `VWF::` to `HTTP::VWF::` in its own code,
and moves its templates from `.../VWF/Display/` to `.../HTTP/VWF/Display/`.

## Keeping in Step With VWF

The modules here are VWF's own, renamed from `VWF::` to `HTTP::VWF::` and
otherwise unchanged, so that a fix belongs in both.  VWF's development tree,
complete with its own demo site, is at
[https://github.com/nigelhorne/vwf](https://github.com/nigelhorne/vwf).

`t/vwf-sync.t` is an author test that holds the two together.  It diffs each
module here against its counterpart in a VWF checkout beside this one, with the
namespace neutralised on both sides, and fails for anything this distribution
has that VWF has not - a fix made here and not given upstream, or an older
revision of a line VWF has since changed.  Lines VWF has and we have not are
reported as a diagnostic rather than a failure, since that is a re-sync waiting
to happen.  POD, blank lines and `$VERSION` are ignored, which is what lets
the two differ by their version numbers and their documentation.

It skips unless `AUTHOR_TESTING` is set, and skips again when no VWF checkout
is found through `$VWF_HOME` or `../vwf`, so it does not run in CI and a CPAN
install is unaffected.

## Compatibility With VWF

VWF has a `README` of its own, describing the framework in the terms its
author uses for it.  Read it beside this one: it is the framework's own
account of itself, and most of it is true of HTTP::VWF as it stands.

Parts of it were written against an earlier design, though, and it does not
always agree with the code it now ships with - in one place it does not agree
with itself.  What follows is the two of them mapped, so that a reader working
from the older document is not misled, and so that a difference is recorded
here rather than left to be discovered.  Where the two disagree, the code is
what runs.

### What That Documentation Describes, That HTTP::VWF Does

- One FastCGI script, with access control and caching

    "The framework handles web requests using FastCGI", "the idea is to create
    page.fcgi", and "access control (including rate limiting), and caching".
    `cgi-bin/page.fcgi` is that script; [HTTP::VWF::Allow](https://metacpan.org/pod/HTTP%3A%3AVWF%3A%3AAllow) is the access control
    and rate limiting, and `FCGI::Buffer` the caching.

- The page that follows the browser

    "the correct index.htm (or index.tmpl) file based on the browser language
    setting (e.g. en-GB) and type (e.g. mobile)".  `CGI::Lingua` gives the
    language and region, and `HTTP::VWF::Display::_types()` the kind of client.
    "The fall back is web, so if a mobile browser visits and there is no specific
    mobile page to display then the web page will be displayed" is exactly how it
    behaves.

- The file extensions

    `.tmpl` goes through the Template Toolkit, `.html` and `.htm` are sent as
    they are, and `.txt` is sent as it is with a `Content-Type` of `text/plain`.
    All three behave as described.  `.tt` is accepted as a second name for a
    Template Toolkit file, and an HTML response says `charset=UTF-8` as well.

- `root_dir`, and the configuration file named after the site

    "The name of the configuration file the sitename, e.g.
    /usr/lib/conf/example.com", and "root\_dir /full/path/to/template directory".
    `conf/example.com` in this distribution is that file, and `root_dir` is the
    directory holding the site's `templates/`, as described.

    Both the plain form the document shows and the XML form the example uses are
    read - `Config::Abstraction` takes either, and so does `Config::Auto`, which a
    site's own code may still be reading its configuration with.  A site whose
    configuration is already written the old way does not have to be converted.
    Note that the snippet in the document is a description rather than a file to
    copy: it writes `root_dir /path` with a space but `memory_cache:` and
    `disc_cache:` with colons, and a file mixing the two separators is liable to
    have the explanations taken as the values, or to be refused outright as not
    being in a format that can be read.

    `t/config-format.t` holds this: it writes each form in a temporary directory
    and reads it back through each reader.

    The document's own FIXME - "Configuration files should be in .../conf, not
    .../lib/conf" - is honoured: a site's `conf/` sits at the top of the search
    order, beside `cgi-bin/`, and a setting in it is not overridden by a leftover
    copy of the file in one of the `lib/conf` directories that predate it.  That is
    where `page.fcgi` has always read the file, and [HTTP::VWF::Display::table](https://metacpan.org/pod/HTTP%3A%3AVWF%3A%3ADisplay%3A%3Atable)
    reads it from there too: it used to look only in `~/lib/conf`, which left a
    site declaring its `root_dir` in `conf/` and in `~/lib/conf` both, and free to
    have the two disagree.

- Debugging from the command line

    `perl -c -Ilib cgi-bin/page.fcgi`, `--mobile`, `--search-engine`,
    `lang=fr`, `key=value` and `lint_content=0` all work as the document's
    "Usage" section shows.  The `--mobile` and `--search-engine` flags are
    CGI::Info's, read from `@ARGV`, so they are available to any script that uses
    it.

- Data in the site's own directories

    "Data stored in the files .../databases/ ... CSV, XML and SQLite format files
    are supported."  There are two directories in play, and both are read.
    [HTTP::VWF::Display::table](https://metacpan.org/pod/HTTP%3A%3AVWF%3A%3ADisplay%3A%3Atable) reads `root_dir/databases/`, which is the
    `.../databases/` the document names.  `page.fcgi` separately opens the
    directory beside it - `data/`, next to its own `cgi-bin/` - through
    Database::Abstraction, and hands `databasedir` to the template, which is what
    serves CSV, XML and SQLite.

- The `save_to` caveat

    "Every time you upload a new site ensure that you remove the save\_to
    directory, since that contains cached copies of pages that will be inconsistent
    with the new site."  Still true, and still worth doing: `page.fcgi` keeps a
    day's worth of rendered pages under `root_dir/save_to`.

### Where That Documentation Has Moved On

- The shape of the template path

    The document gives the hierarchy as
    `.../language/region/[web|mobile|robot|search]/filename.[html|tmpl|txt]`, and
    four paragraphs later shows it the other way round, as
    `.../web/en/index.tmpl`.  The code searches both, the kind of client first:
    for each kind, `<kind>/<language>/<region>`, then
    `<kind>/<language>`, then `<language>/<kind>`, then
    `<kind>/default`, then `default/<kind>`, then `<kind>` alone,
    and finally the fall-back sequence `web`, `default/web`, `default` and the
    templates directory itself.

    The filename is not the page's name either: the path ends with the page's own
    class path, so `HTTP::VWF::Display::index` is sought as
    `templates/en/web/HTTP/VWF/Display/index.tmpl`.  The worked example in the
    document, `templates/VWF/index.html`, is from before pages gained the
    `Display::` component, so it would now be
    `templates/HTTP/VWF/Display/index.html`.

    `ai` is a kind of client the document does not list: an AI crawler, which
    `CGI::Info::is_ai()` recognises and which falls back to the `robot` and
    `search` templates before `web`.  A search engine likewise falls back to
    `robot`, and a robot to `search`.

- One script, not one per page

    "You'll need to create cgi-bin files for each of your page sets (e.g. create
    foo.fcgi for .../web/\*/\*/foo.html) ... change the two places that VWF::index
    appear to VWF::foo."  That was the design when it was written, and the
    commented-out line that did it is still in `page.fcgi`.  Now one `page.fcgi`
    serves every page: the page is named by the `page` parameter, and only those
    the configuration allows can be loaded.  A request that names no page at all is
    answered with a 300 listing the pages that may be asked for.

- Installing the framework

    "copy the contents of the lib directory to /usr/lib/VMF (or a place of your
    choice)" and "modify index.fcgi changing the 'use /usr/lib' directive"
    describe installing the framework into a site by hand.  That step is what this
    distribution replaces: HTTP::VWF is installed, and a site's `use lib` line
    only has to reach the site's own page subclasses, if it has any.

    The `lazy` step in the document's "Overview" is no longer needed either -
    nothing here uses `lazy`, and the dependencies are declared in `Makefile.PL`
    and `cpanfile`.

- The logging configuration

    "Finally change conf/index.l4pconf to the logging mechanism of your choice."
    Logging is configured in the domain configuration file now, in the
    `<logger>` section that Log::Abstraction reads, so this distribution ships
    no `l4pconf` file: nothing would read it.

- The redirect

    The `.htaccess` the document shows redirects `/index.html` to
    `/cgi-bin/index.fcgi`.  The script this distribution ships is
    `cgi-bin/page.fcgi`; the document uses both names for it.

### What Changes for a Site That Uses This Distribution

- Every `VWF::` is `HTTP::VWF::`

    The document names `VWF::Display`, `VWF::Config`, `VWF::Allow` and the rest,
    and a page subclasses `VWF::Display`.  Here they are `HTTP::VWF::Display`,
    `HTTP::VWF::Config`, `HTTP::VWF::Allow` and the rest, and a page writes
    `use parent 'HTTP::VWF::Display'`.

- The template directory gains a level

    Because the page's class path is part of the template path,
    `.../VWF/Display/` becomes `.../HTTP/VWF/Display/`.

## Site Settings

A site describes itself in the configuration file named after its domain, in
its own `conf/` beside `cgi-bin/`.  These are the settings this
distribution's own `cgi-bin/page.fcgi` reads; a site that adapts that script
reads the same ones.

Each has a default, and every default is the value that used to be written into
the script - so a site that says nothing about a setting behaves exactly as it
did before the setting existed.  `t/site-config.t` holds the defaults in place,
so one cannot drift unnoticed.

- `database_dir`

    Where the site's databases are, as `Database::Abstraction` reads them, and what
    a page is given as `databasedir`.  Default: `data/`, beside `cgi-bin/`.

- `data_modules`

    The data modules the site loads.  Each is loaded, constructed with `->new()`
    and given to every page under the last part of its name, lower-cased, so that a
    site's `Bands::Data::bands` arrives at the page as `bands`.  Default:
    `HTTP::VWF::Data::index`, which is the handle [HTTP::VWF::Display::index](https://metacpan.org/pod/HTTP%3A%3AVWF%3A%3ADisplay%3A%3Aindex)
    needs.  The access log is not one of these: `page.fcgi` builds its reader
    itself from the `vwflog` setting, since it has to be told which log to read.

- `supported_languages`

    The languages the site offers, for example `en-gb fr`.  `CGI::Lingua` negotiates
    within this list, so a language's templates are only reachable once it is listed.
    Default: `en-gb`.

- `allow_ips`

    Addresses allowed through the geo-block, passed to `CGI::ACL`'s `allow_ip()`.
    An address here is still refused if its reverse DNS says it is in a cloud range,
    and [HTTP::VWF::Allow](https://metacpan.org/pod/HTTP%3A%3AVWF%3A%3AAllow) has checks of its own that this does not bypass.  Default:
    `108.44.193.70` and `127.0.0.1`, the first being one site's own address, kept so
    that the sites this script came from keep working.  A site with an address of its
    own should set this.

    It is not called `allowed_ips`, and cannot be: that is a `CGI::ACL`
    constructor argument, and `CGI::ACL`'s `new()` runs the site's configuration
    through `Object::Configure::configure()`, which would hand a key of that name to
    it as a string where a hash is expected - breaking access control outright.

- `rate_limit_trusted_ips`

    Addresses exempt from rate limiting.  Default: `127.0.0.1` and `192.168.1.1` -
    loopback, and one private address.

- `pages`

    The pages `?page=` may load.  Without it, every `Display/*.pm` shipped here may
    be loaded except `captcha`.  See [HTTP::VWF::Display](https://metacpan.org/pod/HTTP%3A%3AVWF%3A%3ADisplay).

- `blacklist_countries`

    The countries refused access.  See [HTTP::VWF::Blacklist](https://metacpan.org/pod/HTTP%3A%3AVWF%3A%3ABlacklist).

- `vwflog`

    Where the access log is written, and read back by the meta-data page.  Default:
    `vwf.log` in the directory `CGI::Info` reports as the log directory.

A list-valued setting can be written as one string of values separated by commas
or spaces, or as an element with one child per value, so that an XML
configuration file can hold a list in whichever way reads better:

```
    <allow_ips>108.44.193.70, 127.0.0.1</allow_ips>

    <allow_ips>
            <ip>108.44.193.70</ip>
            <ip>127.0.0.1</ip>
    </allow_ips>
```

`conf/example.com` carries each of these settings as a commented example.

## Optional Prerequisites

Two of the modules the framework can use are recommended rather than required,
because neither can be installed everywhere and a site works without them:

- `Filesys::Df`

    The disk usage figure on the meta-data page.  Its own `Makefile.PL` refuses
    Windows - it prints "This module does not support Windows" and points at
    `Filesys::DfPortable` - so this distribution does not declare it there at all.
    Requiring it would make `cpanm --installdeps` fail and HTTP::VWF impossible to
    install on Windows.  Without it the meta-data page leaves the figure out.

- `XML::LibXML`

    The parser [HTTP::VWF::Allow](https://metacpan.org/pod/HTTP%3A%3AVWF%3A%3AAllow) reads the DShield feed with.  It links against a
    system `libxml2`, which Strawberry Perl does not ship, so it does not build on
    Windows either.  Without it [HTTP::VWF::Allow](https://metacpan.org/pod/HTTP%3A%3AVWF%3A%3AAllow) says once that it is skipping
    the feed and carries on; the checks after that point in the module still run,
    as they do when the feed cannot be downloaded.

Everything else in `Makefile.PL` is required on every platform.  Both of these
are loaded when they are first needed rather than with `use`, so neither is
needed to install this distribution, and the test suite passes without them.

## License

Licensed under GPL2.0 for personal use only.

## Author

Nigel Horne, `<njh at nigelhorne.com>`
