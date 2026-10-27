#!/usr/bin/env perl

# The examples' front doors, as a test: each example carries an F<index.html> that
# sends a visitor on to a page of the site, and both halves of that can go stale.
# The script it names can be renamed or moved; the page it asks for can stop being
# one the site offers, or stop having a template to render it, or stop being in the
# site's database.  Nothing else in the suite reads those files - the renders
# t/page-render.t drives reach the script directly, as the run recipes in the
# examples' READMEs do - so this test reads them: it takes the forward out of each
# front door, requires the path it names to be there and to be a program a web
# server can run, and requires what it asks that script for to be something the
# site has.  A front door that points at a page the site would refuse, or at a key
# its database does not hold, fails here rather than in a visitor's browser.
#
# What "something the site has" means depends on what the door asks for, and the
# two examples ask for different things.  A framework page script dispatches
# C<?page=>, so that value has to be a page the site offers: named by its C<<
# <pages> >> setting, when it has one, and with a template or a module to render
# it.  A site with a page of its own names its own parameter - the links example's
# C<?entry=> is a key in its database - so a value that is not a page is looked for
# among the keys the site's own CSV files hold.  Both checks are of the site's
# files, not of a running script, so this test needs no server, no network and no
# configuration of the machine's own.
#
# The check is by the example directory discovered under F<examples/>, so a new
# example is covered as soon as it has a front door.  If its door asks for
# something neither of the shapes above describes, this test says so instead of
# passing it silently.

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Find;
use File::Spec;
use FindBin qw($Bin);
use Test::Most;

# Under prove -t, $Bin is tainted; detaint it before it reaches a file name.  The
# match is a statement of its own: with the match in the same expression as the
# declaration, warnings::unused counts the variable as unused, and the Linux
# workflow's sweep for unused variables fails the step on it.
my $root = do {
	my $dir = File::Spec->catdir($Bin, File::Spec->updir());
	$dir =~ /\A(.*)\z/s;
	abs_path($1);
};

my @front_doors = sort glob(File::Spec->catfile($root, 'examples', '*', 'index.html'));

plan skip_all => "No example carries a front door: $root/examples/*/index.html"
	unless(@front_doors);

# The file's contents.  One small file is read per front door, which does not need
# a dependency to read it.
sub slurp
{
	my $file = shift;

	open(my $fh, '<', $file) or return;
	local $/;
	return <$fh>;
}

# Where a front door sends a visitor: the URL of its refresh, out of whichever meta
# element carries one.  Returns nothing when the file carries no forward at all,
# which is the case a front door cannot survive.
sub forward_url
{
	my $html = shift // '';

	foreach my $meta ($html =~ m{<meta\b[^>]*>}gi) {
		next unless($meta =~ m{http-equiv\s*=\s*["']?Refresh["']?}i);

		my ($content) = $meta =~ m{content\s*=\s*["']?([^"'>]+)}i;
		next unless(defined($content));

		my ($url) = $content =~ /\bURL\s*=\s*(\S+)/i;
		return $url if(defined($url));
	}

	return undef;
}

# The pages a site offers, from the <pages> settings in whatever its conf/ holds.
# Comments are dropped first, so a list left commented out does not answer for the
# site.  Finding nothing means the site does not limit them, which is the
# framework's own default: every page the distribution ships may be loaded.
sub pages_offered
{
	my $example = shift;
	my @pages;

	foreach my $file (sort glob(File::Spec->catfile($example, 'conf', '*'))) {
		next unless(-f $file);

		my $config = slurp($file) // '';
		$config =~ s{<!--.*?-->}{}gs;

		foreach my $list ($config =~ m{<pages>(.*?)</pages>}gs) {
			push @pages, grep { length } split(/\s+/, $list);
		}
	}

	return @pages;
}

# Whether one file under a directory matches, searched rather than looked for at a
# fixed depth: a template's path is built from its page's class name, so the file
# that renders page C<index> is .../Display/index.tmpl wherever in templates/ the
# site has put it.
sub find_one_matching
{
	my ($base, $subdir, $pattern) = @_;

	my $dir = File::Spec->catdir($base, $subdir);
	return 0 unless(-d $dir);

	my $found = 0;
	File::Find::find({
		no_chdir => 1,
		wanted => sub {
			return if($found);
			my $path = $File::Find::name;
			$found = 1 if(-f $path && $path =~ $pattern);
		},
	}, $dir);

	return $found;
}

# Whether a page has anything to render it: the site's own template, or a module
# for a page whose answer is not a rendering - the links example's page is one of
# those - which the site keeps in its lib/ or the distribution ships in its own.
sub page_has_renderer
{
	my ($example, $page) = @_;

	return 1 if(find_one_matching(
		$example,
		'templates',
		qr{/Display/\Q$page\E\.(?:tmpl|tt|html|htm|txt)\z},
	));
	return 1 if(find_one_matching($example, 'lib', qr{/Display/\Q$page\E\.pm\z}));
	return 1 if(find_one_matching($root, 'lib', qr{/Display/\Q$page\E\.pm\z}));

	return 0;
}

# The keys a site's own databases hold: the first column of every CSV file under
# its data/, after the header line each begins with.  For the links example that
# is the short code of every short URL the site can answer.
sub database_keys
{
	my $example = shift;
	my %keys;

	foreach my $file (sort glob(File::Spec->catfile($example, 'data', '*.csv'))) {
		my @lines = grep { /\S/ } split(/\n/, slurp($file) // '');
		shift @lines;	# the header, which names the columns rather than a key

		foreach my $line (@lines) {
			my ($key) = split(/,/, $line);
			next unless(defined($key));

			# The fields are quoted, as the framework writes them; a key's
			# value is what is between the quotes.
			$key =~ s/\A"//;
			$key =~ s/"\z//;
			$keys{$key} = 1;
		}
	}

	return %keys;
}

foreach my $door (@front_doors) {
	(my $example = $door) =~ s{\Q/index.html\E\z}{};
	my $where = File::Spec->abs2rel($example, $root);

	subtest $where => sub {
		my $url = forward_url(slurp($door));

		ok(defined($url), 'the front door forwards a visitor somewhere')
			or diag("no refresh naming a URL in it: $door");
		return unless(defined($url));

		# An address of its own would take the visitor off the site and leave the
		# pages unreachable, and a path from the root only works when the site is
		# the document root - which is not the site's own layout.
		unlike($url, qr{\A[A-Za-z][A-Za-z0-9+.\-]*:},
			'the forward keeps the visitor on the site');
		unlike($url, qr{\A/}, '   and is relative to the script, not to a document root of its own');

		# Neither of those can be recovered from: a forward that is not a path in
		# the site names no file to look for, and what the rest checks is a file.
		return if($url =~ qr{\A(?:[A-Za-z][A-Za-z0-9+.\-]*:)?/});

		my ($path, $query) = split(/\?/, $url, 2);

		my $script = File::Spec->catfile($example, split(m{/}, $path));
		ok(-f $script, "the script it names, $path, is there") or return;

		SKIP: {
			skip 'there is no executable bit to check on Windows', 1 if($^O eq 'MSWin32');
			ok(-x $script, '   and is a program a web server can run');
		}

		my %asked = map { split(/=/, $_, 2) }
			grep { /=/ } split(/[&;]/, $query // '');

		unless(%asked) {
			# A script answers a request that names nothing itself: the
			# framework's script lists the pages it serves, and a site whose one
			# page is its own answers with that page.  Neither needs anything of
			# the site beyond the script, which is checked above.
			ok(1, 'the front door names no page, so the script answers the request itself');
			return;
		}

		foreach my $name (sort keys %asked) {
			my $value = $asked{$name};

			if($name eq 'page') {
				# A site that lists the pages ?page= may load refuses the others,
				# so a front door naming one of those is a door to a refusal.  A
				# site that lists none leaves it to the framework's defaults.
				my @pages = pages_offered($example);
				my $offered = @pages ? scalar(grep { $_ eq $value } @pages) : 1;
				ok($offered, "the page it asks for, $value, is one the site offers")
					or diag('the site offers: ', (@pages ? join(' ', @pages) : '(every page the distribution ships)'));

				ok(page_has_renderer($example, $value),
					'   and there is a template or a module to render it');
			} else {
				# A site whose page names its own parameter - the links example's
				# ?entry= is one - keeps its values in its database, so that is
				# where a value that is not a page is looked for.
				my %keys = database_keys($example);
				ok($keys{$value}, "the $name it names, $value, is a key in the site's own database")
					or diag(
						"a parameter that is neither ?page= nor a key in the site's databases\n",
						"is one this test cannot check, so it fails rather than passes: $name=$value\n",
						'its databases hold: ', (join(' ', sort keys %keys) || '(no keys)'),
					);
			}
		}
	};
}

done_testing();
