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
adapt; `templates/`, `conf/` and `data/` beside it are the site it serves.
See `README.md` for how to set a site up, and `CLAUDE.md` for how the request
is handled once it arrives.

## Keeping in Step With VWF

The modules here are VWF's own, renamed from `VWF::` to `HTTP::VWF::` and
otherwise unchanged, so that a fix belongs in both.  VWF's development tree,
complete with its own demo site, is at
[https://github.com/nigelhorne/vwf](https://github.com/nigelhorne/vwf).

## License

Licensed under GPL2.0 for personal use only.

## Author

Nigel Horne, `<njh at nigelhorne.com>`
