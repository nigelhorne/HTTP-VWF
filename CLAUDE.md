# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

HTTP::VWF is VWF (Versatile Web Framework), a Perl-based MVC FastCGI web
framework, packaged as a CPAN distribution.  It builds responsive sites that
adapt to browser language, client type (web/mobile/robot/search/ai) and multiple
database back ends.

**This distribution is a rename of VWF, not a fork.**  The modules are VWF's
own, with `VWF::` changed to `HTTP::VWF::` on the way in and nothing else
changed, so that the two can still be compared line by line.  A change made to
a module here belongs in VWF too, and vice versa.

The VWF development tree is at https://github.com/nigelhorne/vwf.  In a
workspace with both checkouts side by side it is usually `../vwf`, and the
module `lib/HTTP/VWF/Display.pm` here corresponds to `lib/VWF/Display.pm`
there.

Sites that used to carry a renamed copy of VWF of their own - `ged2site`,
`pds`, `Geo::Coder::Free`, `syslogd` and the bandsman.co.uk,
concert-bands.co.uk and nigelhorne.com websites - are the reason this
distribution exists: they can depend on it instead.

## Commands

### Syntax Checks
```bash
perl -MO=Lint cgi-bin/page.fcgi		# needs B::Lint
perl -c -Mwarnings::unused cgi-bin/page.fcgi
```

### Run Tests
```bash
# Full test suite
prove t/

# Single test file
perl t/security_tests.t
perl t/blacklist.t

# These two have no .t suffix, so prove t/ skips them; CI runs them by name
cd t && prove get_params && root_dir=$(realpath ..) prove get_template_path

# Author-only: diff these modules against the VWF checkout (see below)
AUTHOR_TESTING=1 prove -l t/vwf-sync.t
```

Dependencies for the suite: `Test::Most`, `Test::MockObject` and
`Test::DescribeMe` are declared in `Makefile.PL`; `IP::Country::Fast` and `CGI::ACL` are needed for the GeoIP
parts of `t/blacklist.t`, which skip themselves if they are absent.

Tests must not depend on files outside the repository.  `HTTP::VWF::Display`
falls back to `~/lib/conf` when it can't find a config directory, so a test can
pass locally and fail in CI.  Point `CONFIG_DIR` at a temporary directory
holding a `default` config file instead (see `t/captcha_tests.t`).  Running the
tests with `HOME` set to an empty directory reproduces CI.  Hand-written
`CGI::Info` mocks (e.g. `MockInfo` in `t/get_template_path`) must define every
`is_*` method that `HTTP::VWF::Display::_types()` calls.

Note that `t/get_template_path` reads its templates from
`$ENV{'root_dir'}`, so it must be run with that set to the distribution root:

```bash
cd t && root_dir=$(realpath ..) prove get_template_path
```

### Manual Functional Testing
```bash
# Basic page render
LANG=en_GB root_dir=$(pwd) cgi-bin/page.fcgi page=index

# Mobile simulation
root_dir=$(pwd) cgi-bin/page.fcgi --mobile page=index lang=fr

# With config directory
CONFIG_DIRECTORY=../conf perl cgi-bin/page.fcgi page=index
```

`page.fcgi`'s second `use lib` puts `~/lib/perl5` ahead of the installed
modules in `@INC`, so a copy of HTTP-VWF there is loaded instead of this
checkout's `lib/`.  To run the repository's modules, set `HOME` to a directory
without `lib/perl5`.

## Architecture

### Request Flow

1. `cgi-bin/page.fcgi` receives the FastCGI request
2. `HTTP::VWF::Config` loads XML config hierarchically (environment → domain config)
3. `HTTP::VWF::Allow` enforces rate limits (soft/hard thresholds) and blocks blacklisted IPs/countries/user agents
4. CAPTCHA challenge served if rate limit exceeded (`HTTP::VWF::CAPTCHA` wraps Google reCAPTCHA)
5. `CGI::Lingua` detects language and region from request headers
6. `HTTP::VWF::Display` resolves the template path and delegates to the page-specific subclass (`HTTP::VWF::Display::<page>`)
7. Template Toolkit renders the `.tmpl`/`.html`/`.txt` template
8. `FCGI::Buffer` sends the response with HTTP 304 optimization and caching headers

### Key Modules

| Module | File | Role |
|---|---|---|
| `HTTP::VWF::Config` | `lib/HTTP/VWF/Config.pm` | Hierarchical XML config loading with env overrides |
| `HTTP::VWF::Display` | `lib/HTTP/VWF/Display.pm` | Template resolution, response generation, security headers, HTTP/2 preload hints |
| `HTTP::VWF::Display::<page>` | `lib/HTTP/VWF/Display/*.pm` | Per-page rendering logic |
| `HTTP::VWF::Data::<source>` | `lib/HTTP/VWF/Data/*.pm` | Data access layer (CSV, XML, SQLite via Database::Abstraction) |
| `HTTP::VWF::Allow` | `lib/HTTP/VWF/Allow.pm` | Access control, rate limiting (Data::Throttler), country blocking |
| `HTTP::VWF::Blacklist` | `lib/HTTP/VWF/Blacklist.pm` | The country blacklist, shared by `page.fcgi`, `HTTP::VWF::Allow` and `HTTP::VWF::Display` |
| `HTTP::VWF::Utils` | `lib/HTTP/VWF/Utils.pm` | Cache initialisation (CHI), Haversine distance |
| `HTTP::VWF::CAPTCHA` | `lib/HTTP/VWF/CAPTCHA.pm` | reCAPTCHA integration and bypass logic |

### Template Resolution

Templates are resolved in priority order, falling back through specificity
levels.  The page's namespace is a directory in the middle of the path, so
`HTTP::VWF::Display::index` resolves as:

```
templates/[lang]/[region]/[device]/HTTP/VWF/Display/[page].[tmpl|html|txt]
templates/[lang]/default/[device]/HTTP/VWF/Display/[page].[tmpl|html|txt]
templates/default/[device]/HTTP/VWF/Display/[page].[tmpl|html|txt]
```

Device types: `web`, `mobile`, `robot`, `search`, `ai` (AI crawlers, from
`CGI::Info::is_ai()`; falls back to `robot`, then `search`, then `web`
templates)

### Configuration

Domain config lives in `conf/<domain>/` as XML files, or a single
`conf/<domain>`; `conf/example.com` is a complete example.  Key settings:
`root_dir`, `memory_cache`, `disc_cache`, reCAPTCHA keys, rate limit thresholds
(soft: 100 req/60s, hard: 150 req/60s), and blacklisted countries/user agents.
Log4perl config is in `conf/*.l4pconf`.

The country blacklist lives in `HTTP::VWF::Blacklist`
(`lib/HTTP/VWF/Blacklist.pm`), shared by `page.fcgi` (CGI::ACL),
`HTTP::VWF::Allow` and `HTTP::VWF::Display`; override it with
`blacklist_countries` (e.g. `<blacklist_countries>CN, RU</blacklist_countries>`).
Only pages on an allow-list can be loaded: `pages` in the config (e.g.
`<pages>index, meta_data</pages>`), or by default every
`lib/HTTP/VWF/Display/*.pm` beside `page.fcgi` except `captcha`.

The CSRF token requires a secret to be set in config:

```xml
<security>
  <csrf>
    <secret>your-secret-here</secret>
  </csrf>
</security>
```

If absent, HTTP::VWF generates a cryptographically random per-process secret on
first use and logs a one-time warning.  Protection remains strong, but tokens
are invalidated on process restart (users with open forms must reload).
Configure the secret to suppress the warning and avoid that edge case.  To
disable CSRF entirely, set `<enable>0</enable>` inside `<csrf>`.

### Caching

Two-tier: in-process memory cache (CHI::Driver::Memory) and optional
disc/Memcached cache.  Cache keys incorporate language, region, device type, and
page parameters to serve correct variants.

### Security Model

Several layers of defence are applied on every request, in order:

1. **CGI::ACL** — blocks cloud provider IP ranges and blacklisted countries
2. **`blacklisted()`** — rejects IPs that have sent SQL-injection strings this process lifetime; uses bounded-quantifier regexes to prevent ReDoS
3. **HTTP::VWF::Allow** — DShield feed check, user-agent blacklist, Data::Throttler rate limit, CGI::IDS intrusion detection
4. **Rate limiter** — soft limit (default 100 req/60s) triggers CAPTCHA; hard limit (1.5×) blocks until CAPTCHA is solved, or, with reCAPTCHA disabled, returns 429 with `Retry-After` until the window expires
5. **CAPTCHA** — Google reCAPTCHA via `HTTP::VWF::CAPTCHA`; a verified solve stores a short-lived bypass token in the rate-limit cache

All page modules are loaded via `Module::Runtime::require_module` — never via
string `eval` — to eliminate code-injection risk from the user-supplied page
name.  Only pages on the allow-list (see Configuration) are loaded; anything
else gets a 404.

`HTTP::VWF::Display::new()` also throttles (Data::Throttler, `throttle` config:
default 30 requests per 90 seconds) and returns `undef` with status 429 for a
throttled client; `page.fcgi` then sends a 429 with `Retry-After`.

The CSV access log (`vwf.log`) passes every field through `_csv_escape()` to
prevent CSV injection and spreadsheet formula injection.

### HTTP Status Lines

Once `page.fcgi` has created its `FCGI::Buffer` (`$fb`), set the status with
`$info->status()` and do not print a `Status:` line: FCGI::Buffer sends one from
`$info->status()`, and printing your own produces a duplicate.  Before `$fb`
exists (the CAPTCHA redirect, the rate limiter and the access-control 403),
nothing else sends the status, so those paths must print it.  Plain-text error
responses go through `send_error(status => ..., body => ..., headers => ...,
buffered => 1)`, which sets `$info->status()` and omits the `Status:` line when
`buffered` is true.

### HTTP/2 Preload Hints

`HTTP::VWF::Display` supports `Link: rel=preload` headers for HTTP/2 server
push.  Page subclasses register render-critical assets from their constructor:

```perl
package HTTP::VWF::Display::index;
use parent 'HTTP::VWF::Display';

sub new {
    my ($class, @args) = @_;
    my $self = $class->SUPER::new(@args);
    return unless defined $self;

    $self->add_preload('/css/main.css',       'style')
         ->add_preload('/fonts/body.woff2',   'font')   # crossorigin set automatically
         ->add_preload('/js/index.js',        'script');

    return $self;
}
```

`add_preload` must be called from the constructor, not from `html()`, because
`http()` (which emits the headers) runs first.  The base class preloads nothing
— VWF owns no assets, and each page subclass knows its own dependencies.  See
`perldoc HTTP::VWF::Display` for full parameter documentation.

## Keeping in step with VWF

Because this distribution is a rename of VWF, a fix belongs in both.  When you
change a module here, check whether `../vwf` has the same file and whether the
change applies there too; the reverse holds as well.

`t/vwf-sync.t` is an author test that checks this for you.  It diffs each of
the 14 modules here against its counterpart in the VWF checkout, with the
namespace neutralised on both sides, and fails for any line this distribution
has that VWF does not - whether that is a fix made here and not given upstream,
or an older revision of a line VWF has since changed.  Lines VWF has and we do
not are reported as a diagnostic rather than a failure, since that is a re-sync
waiting to happen.  POD, blank lines and `$VERSION` are ignored, which is what
lets the two differ by their version numbers and their documentation.

It skips unless `AUTHOR_TESTING` is set, and skips again if no VWF checkout is
found through `$VWF_HOME` or `../vwf`, so it does not run in CI and a CPAN
install is unaffected:

```bash
AUTHOR_TESTING=1 prove -l t/vwf-sync.t
VWF_HOME=~/src/njh/vwf AUTHOR_TESTING=1 prove -l t/vwf-sync.t
```

It also checks the table of tracked modules against both trees, so a module
added to one side and not the other is reported rather than silently skipped.
`lib/HTTP/VWF.pm` is deliberately outside the comparison: it is this
distribution's own front door and VWF has no `VWF.pm` to compare it against.

Sites that still carry their own renamed copy use the same kind of test - see
`Geo::Coder::Free`'s `t/vwf-sync.t`.
