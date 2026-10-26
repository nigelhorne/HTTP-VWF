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
adapt; C<templates/>, C<conf/> and C<data/> beside it are the site it serves.
See F<README.md> for how to set a site up, and F<CLAUDE.md> for how the request
is handled once it arrives.

=head1 Keeping in step with VWF

The modules here are VWF's own, renamed from C<VWF::> to C<HTTP::VWF::> and
otherwise unchanged, so that a fix belongs in both.  VWF's development tree,
complete with its own demo site, is at
L<https://github.com/nigelhorne/vwf>.

=head1 LICENSE

Licensed under GPL2.0 for personal use only.

=head1 AUTHOR

Nigel Horne, C<< <njh at nigelhorne.com> >>

=cut

1;
