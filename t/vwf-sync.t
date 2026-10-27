#!perl -w

# Author test: how far this distribution has drifted from the VWF checkout it
# is a copy of.
#
# This distribution is VWF, not a fork of it.  Each module here is VWF's own
# file, renamed from VWF:: to HTTP::VWF:: on the way in and otherwise unchanged,
# which is what makes the two comparable at all.  Nothing else is supposed to
# differ, so anything that does is one of three things:
#
#   - a fix made here that VWF has not been given.  It belongs upstream: VWF is
#     the authority on its own code, and the next copy taken from it would
#     discard the fix;
#   - a fix made in VWF that has not been copied here yet.  That is a re-sync
#     waiting to happen, and the report counts those lines separately;
#   - a divergence that is meant to stay.  There is no list of those, because
#     there is not meant to be one, so the first one to appear should be a
#     decision recorded in VWF's Changes file or in this test, not a silent
#     difference.
#
# This test diffs VWF's file against ours and fails for every block of lines
# ours has that VWF's has not.  A block rather than a line, so that a subroutine
# added to a tracked file is one failure naming its whole body.
#
# A block is one of two things, and they are reported apart because what to do
# about them is different:
#
#   - code this distribution has added, which a re-sync will discard.  VWF has
#     never had those lines, so there is nothing upstream to merge them into and
#     they belong in VWF first;
#   - an older revision of a line VWF has since changed, which a re-sync will
#     replace.  VWF's revision is printed beside ours, because a local change
#     made on top of that line has to be re-applied to it.
#
# The two files part company in passages: between one pair of lines the two
# share and the next, each file has lines the other has not.  A local line whose
# passage holds none of VWF's lines, or none that read like it, is the first
# kind.  A local line that reads like one of VWF's lines in the same passage is
# the second kind, and that line is the one that will replace it.  "Reads like"
# is measured on the words of the two lines (identifiers and numbers,
# punctuation and whitespace ignored): a line is called a rewrite when at least
# half the words on either side are shared, which is what a changed line looks
# like and what an inserted one usually does not.  A line that could be either
# is reported as code VWF has never had, because that is the reading that sends
# the reader to look at the difference.  Lines next to each other with the same
# answer, inside one run of consecutive local lines, are one block: a changed
# line beside an added subroutine is reported as a rewrite of one of VWF's lines
# and an addition of the rest, and the range a failure prints is the lines it
# printed.
#
# What the comparison does not see:
#
#   - a line VWF has and we have not is a diagnostic, not a failure.  Our copy
#     being behind VWF is a different problem from local code being at risk, and
#     the re-sync is what brings those lines in.  A local deletion with nothing
#     put in its place is therefore not caught;
#   - POD, blank lines and the $VERSION line are ignored, so a reworded
#     paragraph or a version bump is not an addition.  These are the differences
#     a copy is expected to have: every module here carries this distribution's
#     version, which is not VWF's, and Display.pm and this distribution's front
#     door carry POD of their own.  A paragraph of local POD standing on its own
#     would not be reported;
#   - the namespace, which is neutralised on both sides rather than allowed for
#     on one, so that what is left is the code and not the name it is filed
#     under;
#   - the comparison is textual.  A reindented or reflowed copy of an upstream
#     line reads as a local addition;
#   - a line VWF has rewritten into something sharing none of its words reads as
#     local code: the words are what says the two are the same line, and a
#     rewrite that keeps none of them leaves nothing to go on.
#
# The poison of a test like this is that a comparison which has quietly stopped
# working reports no differences and passes, so the comparison is first run here
# on source whose answer is known.
#
# VWF is found through $VWF_HOME, or as ../vwf beside this checkout.  Without
# one the test skips, so a CPAN install is unaffected, and so is a workspace
# that does not carry VWF.
#
#   AUTHOR_TESTING=1 prove -l t/vwf-sync.t
#   VWF_HOME=~/src/njh/vwf AUTHOR_TESTING=1 prove -l t/vwf-sync.t

use strict;
use warnings;

use Cwd ();
use File::Find ();
use File::Spec;
use FindBin qw($Bin);
use Test::DescribeMe qw(author);
use Test::Most;

# How alike two runs of lines have to read before a block is called an older
# revision of VWF's rather than code VWF has never had: at least half the words
# on either side are shared (the Dice coefficient over the words of the two
# runs).  A changed line shares most of its words with its older revision; an
# inserted one usually shares none.
my $ALIKE_ENOUGH = 0.5;

# The modules this distribution carries from VWF, as paths relative to the
# namespace directory: lib/HTTP/VWF/<name> here is lib/VWF/<name> in VWF.  Add
# an entry when another module becomes a copy of one of VWF's.
my @TRACKED = (
	'Allow.pm',
	'Blacklist.pm',
	'CAPTCHA.pm',
	'Config.pm',
	'Data/index.pm',
	'Data/vwf_log.pm',
	'Display.pm',
	'Display/captcha.pm',
	'Display/editor.pm',
	'Display/index.pm',
	'Display/meta_data.pm',
	'Display/table.pm',
	'Display/upload.pm',
	'Throttle.pm',
	'Utils.pm',
);

# lib/HTTP/VWF.pm is deliberately not here: it is this distribution's own front
# door, holding the version and the overview POD, and VWF has no top-level
# VWF.pm to compare it against.  It sits outside the directory the table below
# enumerates, so its absence is not a gap in the table.

# Under prove -t, $Bin is tainted; detaint it before it reaches a file name.
my $root = do {
	(my $d = File::Spec->catdir($Bin, File::Spec->updir())) =~ /\A(.*)\z/s;
	$1;
};

my $vwf = _master_dir();

if(!defined($vwf)) {
	plan skip_all => 'No VWF checkout to compare against: set VWF_HOME, or put one at ../vwf';
} else {
	diag("VWF read from $vwf");
}

# The table itself
# ---------------------------------------------------------------------------
# A module added to either side and not to the other is the drift this test most
# wants to catch, and a table that simply did not mention it would report
# nothing at all.  So the table is checked against both trees before it is used
# to compare anything.

{
	my @in_master = _modules_in(File::Spec->catdir($vwf, 'lib', 'VWF'));
	my @here = _modules_in(File::Spec->catdir($root, 'lib', 'HTTP', 'VWF'));
	my %tracked = map { $_ => 1 } @TRACKED;

	my @missing_here = grep { !$tracked{$_} } @in_master;
	is_deeply(\@missing_here, [],
		'every module in the VWF checkout has an entry in @TRACKED'
		. ($missing_here[0] ? ': ' . join(', ', @missing_here) . ' has no copy here yet, so port it and add it to @TRACKED' : ''));

	my @missing_there = grep { !$tracked{$_} } @here;
	is_deeply(\@missing_there, [],
		'every module here is one of VWF\'s'
		. ($missing_there[0] ? ': ' . join(', ', @missing_there) . ' has no counterpart in VWF, so either it is this distribution\'s own or the table is out of date' : ''));

	my @gone = grep { !-r File::Spec->catfile($root, 'lib', 'HTTP', 'VWF', $_) } @TRACKED;
	is_deeply(\@gone, [],
		'every tracked module exists here'
		. ($gone[0] ? ': ' . join(', ', @gone) . ' is in the table but not on disk, so VWF has renamed or dropped it' : ''));
}

# The comparison, on literal source
# ---------------------------------------------------------------------------
# The check is only worth anything if it can tell an addition from the
# differences every copy is expected to have, so it is run here on source whose
# answer is known.  Without this, a broken comparison would report no local code
# in any file and the test would pass whatever the tracked files said.

{
	my $master_source = <<'MASTER';
package VWF::Utils;

=head1 VERSION

Version 0.02

=cut

our $VERSION = '0.02';

sub distance {
	return 1;
}
MASTER

	my $our_source = <<'OURS';
package HTTP::VWF::Utils;

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

use Text::xSV::Slurp;

sub distance {
	return 1;
}

sub _local_helper {
	return 1;
}
OURS

	my @master = _code_lines($master_source);
	my @ours = _code_lines($our_source);

	my ($blocks, $behind) = _local_additions(\@ours, \@master);

	is scalar @{ $blocks }, 2,
		'the renamed copy with two additions in it reports two blocks';

	is $blocks->[0]{lines}[0][0], 11,
		'the block for the added use line names the line it is on';
	is $blocks->[0]{lines}[0][1], 'use Text::xSV::Slurp;',
		'the block for the added use line names the line that was added';

	is_deeply [map { $_->[0] } @{ $blocks->[1]{lines} }], [17, 18, 19],
		'the block for the added subroutine spans its whole body';

	# Neither of them is anywhere in VWF, so both are code a re-sync discards --
	# and VWF's lines are an empty list, because there is nothing that will
	# replace them.
	is_deeply [map { $_->{kind} } @{ $blocks }], ['discard', 'discard'],
		'both blocks are reported as code VWF has never had';
	is_deeply [map { $_->{master} } @{ $blocks }], [[], []],
		'and neither is given a revision of VWF to be replaced by';

	# The namespace, the version and the POD are what a copy is expected to
	# differ by, and none of them is an addition.
	is $behind, 0, 'the renamed copy is not reported as behind VWF';
}

# The namespace is neutralised on both sides
# ---------------------------------------------------------------------------
# A copy that renamed its namespace has that one difference in every file, in
# the package line, in every `use`, in every `use parent` and in the middle of
# the template path.  Allowing for it on our side alone would mean the master's
# own files could not be compared at all, so it is replaced on both, and the
# replacement is what the rest of the comparison sees.

{
	is _neutral('package VWF::Display;'), _neutral('package HTTP::VWF::Display;'),
		'the two namespaces read as the same line';
	is _neutral('use parent \'VWF::Display\';'), _neutral('use parent \'HTTP::VWF::Display\';'),
		'a parent class reads as the same line';

	# A bare VWF is the framework's name, and the master and the copy both use
	# it; it has to be neutralised too, or every prose comment mentioning it
	# would read as a local rewrite.
	is _neutral('displayed by VWF thanks'), _neutral('displayed by HTTP::VWF thanks'),
		'a bare mention of the framework reads as the same line';

	# And a word that merely begins with it must not be caught by it.
	isnt _neutral('use HTTP::VWFX::Thing;'), _neutral('use HTTP::VWF::Thing;'),
		'a longer name beginning with the namespace is not swallowed by it';
}

# The two kinds of block, on source whose answer is known
# ---------------------------------------------------------------------------
# Telling them apart is the point of the report -- local code has to be moved
# upstream, an old revision has to be re-applied -- so the distinction is
# checked here as well, including a line VWF has a newer revision of, an
# inserted subroutine, and a local line that is only beside an upstream change
# rather than a revision of it.

{
	my $master_source = <<'MASTER';
package VWF::Utils;

use Carp;

sub distance {
	my ($self, $a, $b) = @_;
	return 2;
}

sub label {
	return 'upstream';
}

sub origin {
	die 'gone';
}
MASTER

	my $our_source = <<'OURS';
package HTTP::VWF::Utils;

use Carp;

sub distance {
	my ($self, $a, $b) = @_;
	return 1;
}

sub _local_helper {
	my ($self, $place) = @_;
	return join('', split(/\s+/, $place));
}

sub label {
	return 'local';
}

sub origin {
	warn 'legacy';
}
OURS

	my ($blocks, $behind) = _local_additions(
		[_code_lines($our_source)], [_code_lines($master_source)]);

	# The lines of each file as written, so that the blocks can be named by the
	# source they came from rather than by a copy of it here: a block reports the
	# number of the line it is on, and the fixture is the only thing that knows
	# what is on it.
	my @our_lines    = split(/\n/, $our_source, -1);
	my @master_lines = split(/\n/, $master_source, -1);

	is scalar @{ $blocks }, 4,
		'the copy reports the four places where it and VWF part company';

	# return 1; is VWF's return 2; in an older revision, and
	# return 'local'; is its return 'upstream';: a re-sync replaces both.  The
	# added subroutine and warn 'legacy';, which stands where VWF's
	# die 'gone'; does, are code VWF has never had, which it discards.
	is_deeply [map { $_->{kind} } @{ $blocks }],
		['replace', 'discard', 'replace', 'discard'],
		'each block is reported as what a re-sync will do to it';

	is_deeply [map { $_->[2] } @{ $blocks->[0]{lines} }], [ $our_lines[6] ],
		'the changed line is the block VWF has another revision of';
	is_deeply [map { $_->[2] } @{ $blocks->[0]{master} }], [ $master_lines[6] ],
		'and the VWF line that will replace it is reported with it';

	# The alignment leaves the brace that closes the subroutine above in this
	# block, because the two files' braces look alike and which pair the
	# subsequence takes is a matter of the table it builds.  The block is the added
	# subroutine either way, and the report prints the lines for the reader to see
	# that for themselves.
	is_deeply [map { $_->[2] } @{ $blocks->[1]{lines} }],
		[ @our_lines[7, 9, 10, 11] ],
		'the inserted subroutine is one block, named line by line';
	is_deeply $blocks->[1]{master}, [],
		'and nothing in VWF will replace it';

	is_deeply [map { $_->[2] } @{ $blocks->[2]{master} }], [ $master_lines[10] ],
		'a reworded line is reported as the VWF line it is a revision of';

	is_deeply [map { $_->[2] } @{ $blocks->[3]{lines} }], [ $our_lines[19] ],
		'a local line beside an unrelated upstream line is not a revision of it';
	is_deeply $blocks->[3]{master}, [],
		'and the VWF line beside it is not offered as a replacement';

	# Three of VWF's lines -- return 2;, return 'upstream'; and
	# die 'gone'; -- are not in ours, which is the other half of the report.
	is $behind, 3, 'VWF has lines ours has not, and they are counted';
}

# The files themselves
# ---------------------------------------------------------------------------

foreach my $name(@TRACKED) {
	my $local_path = File::Spec->catfile('lib', 'HTTP', 'VWF', $name);
	my $local_file = File::Spec->catfile($root, $local_path);
	my $master_file = File::Spec->catfile($vwf, 'lib', 'VWF', $name);

	my $our_text = -r $local_file ? _read_file($local_file) : undef;
	ok(defined($our_text), "$local_path is readable") or next;

	if(-r $master_file) {
		ok(1, "VWF's $name is readable");
	} else {
		# Upstream moving or renaming its own files is a change this test has
		# to be told about: it cannot compare against a file that is not there.
		fail("VWF has no lib/VWF/$name, so $local_path has no master to check against: update the table in this test");
		next;
	}

	my $master_text = _read_file($master_file);

	# The file compared with must be VWF's own.  Comparing our file with a copy
	# of itself would pass whatever we had written into it.
	my $package = _package_of($name, 'VWF');
	like($master_text, qr/^package \Q$package\E;/m,
		"$master_file declares $package, so it is VWF's file and not ours");

	# And the file on our side must be the renamed copy of that one, not a
	# module of its own that happens to share the name.
	my $our_package = _package_of($name, 'HTTP::VWF');
	like($our_text, qr/^package \Q$our_package\E;/m,
		"$local_path declares $our_package, so it is the copy of that one");

	my @ours = _code_lines($our_text);
	my @master = _code_lines($master_text);

	# There has to be something on both sides to compare.  There is no floor on
	# how much: Display/editor.pm is a handful of lines in both, and a floor set
	# for the larger modules would fail on the smaller ones rather than on a
	# comparison that had stopped working.
	cmp_ok(scalar @ours, '>', 0, "$local_path has code to compare");
	cmp_ok(scalar @master, '>', 0, "VWF's $name has code to compare against");

	my ($blocks, $behind) = _local_additions(\@ours, \@master);

	my $local_only = 0;
	$local_only += scalar @{ $_->{lines} } foreach @{ $blocks };

	# A file that shares almost nothing with VWF's file of the same name is not
	# a copy of it, and its entry in the table is a mistake.  This is also what
	# stops the rest of this file from passing by comparing two unrelated
	# modules.
	cmp_ok(scalar(@ours) - $local_only, '>', scalar(@ours) / 2,
		"$local_path is a renamed copy of VWF's $name, not a module of its own");

	# Each block is reported as what a re-sync will do to it, because what to do
	# about it is not the same: local code has to go upstream first, an old
	# revision has to be re-applied on top of VWF's.  For a rewrite VWF's own
	# lines are printed too, so the reader can see the revision that will replace
	# ours without opening VWF's file.
	my ($discarded, $replaced) = (0, 0);

	foreach my $block(@{ $blocks }) {
		my $lines = $block->{lines};
		my $start = $lines->[0][0];
		my $end = $lines->[-1][0];
		my $where = $start == $end ? $start : "$start-$end";
		my $count = scalar @{ $lines };
		my $line_or_lines = $count == 1 ? ' line' : ' lines';

		if($block->{kind} eq 'replace') {
			$replaced += $count;
			fail("$local_path:$where has $count$line_or_lines that VWF's $name"
				. ' has in another revision: a re-sync will replace '
				. ($count == 1 ? 'it' : 'them'));
			diag("    ours: $_->[2]") foreach @{ $lines };
			diag("    vwf:  $_->[2]") foreach @{ $block->{master} };
		} else {
			$discarded += $count;
			fail("$local_path:$where has $count$line_or_lines that VWF's $name"
				. ' has never had: either fix VWF too, or a re-sync will discard '
				. ($count == 1 ? 'it' : 'them'));
			diag("    $_->[2]") foreach @{ $lines };
		}
	}

	if(!@{ $blocks }) {
		pass("$local_path has no code that VWF's $name has not got");
	} else {
		diag("$local_path: a re-sync will discard $discarded "
			. ($discarded == 1 ? 'line' : 'lines') . " of local code and replace $replaced "
			. ($replaced == 1 ? 'line' : 'lines') . ' that VWF has in another revision');
	}

	if($behind) {
		diag("$local_path is behind VWF: VWF's $name has $behind line"
			. ($behind == 1 ? ' that is' : 's that are') . ' not in it.  That is not a '
			. 'failure here, but a re-sync will bring them in, and the two have '
			. 'already parted company.');
	}
}

done_testing();

# ---------------------------------------------------------------------------

# The checkout VWF is read from: $VWF_HOME first, then the two places a
# workspace beside this distribution keeps it.  A directory that is not VWF's
# (no lib/VWF in it) is not one of them.
sub _master_dir
{
	my @candidates = (
		$ENV{'VWF_HOME'},
		File::Spec->catdir($root, File::Spec->updir(), 'vwf'),
		File::Spec->catdir($root, 'vwf'),
	);

	foreach my $dir(grep { defined($_) && length($_) } @candidates) {
		next unless(-d File::Spec->catdir($dir, 'lib', 'VWF'));

		# Resolved, so that the paths in the report read as the checkout they
		# are rather than as the route taken to it.
		return Cwd::abs_path($dir) // $dir;
	}

	return;
}

# The modules under a namespace directory, as paths relative to it, so that the
# table can be checked against both trees.
sub _modules_in
{
	my $dir = shift;

	return if(!-d $dir);

	my @found;

	File::Find::find({
		no_chdir => 1,
		wanted => sub {
			return unless(/\.pm\z/);

			push @found, File::Spec->abs2rel($File::Find::name, $dir);
		},
	}, $dir);

	return sort @found;
}

# The package a module declares, from its path relative to the namespace
# directory: 'Display/upload.pm' is HTTP::VWF::Display::upload here and
# VWF::Display::upload there.
sub _package_of
{
	my ($name, $ns) = @_;

	# Built by joining rather than by interpolating "$ns::$name": that reads
	# as the package variable $ns:: followed by $name.
	my $package = $ns . '::' . $name;
	$package =~ s/\.pm\z//;
	$package =~ s{/}{::}g;

	return $package;
}

sub _read_file
{
	my $file = shift;

	open(my $fh, '<', $file) or return;
	my $text = do { local $/; <$fh> };
	close($fh);

	return $text;
}

# The lines of code in a file, each paired with the number of the line it is on
# in the file it came from: [line number, comparable text, text as written].
#
# POD, blank lines and the $VERSION line are left out.  POD because a reworded
# paragraph is not the kind of addition a re-sync loses in the way that a
# subroutine is; $VERSION because every distribution carries its own, and this
# one is not VWF's; blank lines because they say nothing either way.
sub _code_lines
{
	my $text = shift;

	my @code;
	my $in_pod;
	my $line_number = 0;

	foreach my $line(split(/\n/, $text, -1)) {
		$line_number++;

		# A POD directive starts at column 0; =cut is the one that ends it.
		if($line =~ /^=(\w+)/) {
			$in_pod = ($1 ne 'cut');
			next;
		}

		next if($in_pod);
		next if($line =~ /^\s*\z/);
		next if($line =~ /^\s*our\s+\$VERSION\s*=/);

		push @code, [$line_number, _neutral($line), $line];
	}

	return @code;
}

# A line as it reads in either file.  The namespace is the one thing a copy is
# expected to change, so it is replaced on both sides rather than allowed for on
# one: what is left is the code, not the name it is filed under.  The longer
# name is listed first so that HTTP::VWF is taken whole and not left as
# HTTP::DISTRIBUTION.
sub _neutral
{
	my $line = shift;
	$line =~ s/\b(?:HTTP::VWF|VWF)\b/DISTRIBUTION/g;
	return $line;
}

# What ours has that VWF's has not, and what a re-sync will do with it.
#
# Returns a list of blocks and how many lines VWF's has that ours has not.  A
# block is the lines of one run of local code -- consecutive lines of ours with
# none of the lines the two files share in between, which is why a subroutine
# added to a tracked file is one block naming its whole body -- and a hashref:
#
#   lines  => [[line number, comparable text, text as written], ...]
#   kind   => 'replace' (an older revision of VWF's) or 'discard'
#   master => VWF's lines that will replace ours, for a 'replace'
sub _local_additions
{
	my ($ours, $master) = @_;

	my @blocks;
	my $behind = 0;
	my @passage;

	foreach my $segment(_diff($ours, $master)) {
		my ($side, $lines) = @{ $segment };

		# A line the two share ends the passage: what is on either side of it
		# belongs to different parts of the file.
		if($side eq 'both') {
			_classify_passage(\@passage, \@blocks) if(@passage);
			@passage = ();
			next;
		}

		$behind += scalar @{ $lines } if($side eq 'master');
		push @passage, $segment;
	}

	_classify_passage(\@passage, \@blocks) if(@passage);

	return (\@blocks, $behind);
}

# The blocks of one passage, each with what a re-sync will do to it.
#
# A local line is a revision of one of VWF's when that line reads like it (see
# $ALIKE_ENOUGH), and VWF's line is carried with it so that the report can print
# both revisions side by side.  The verdict is made line by line and then
# adjacent lines with the same verdict are run together, because the two answers
# belong to the same run of local lines as often as not: a changed line beside
# an added subroutine is a rewrite of one of VWF's lines and an addition of the
# rest, and whoever reads the report has to be told both, once each.
sub _classify_passage
{
	my ($passage, $blocks) = @_;

	my @master;
	foreach my $run(grep { $_->[0] eq 'master' } @{ $passage }) {
		push @master, @{ $run->[1] };
	}

	my @blocks_of_passage;

	foreach my $run(grep { $_->[0] eq 'ours' } @{ $passage }) {
		# A block stays inside one run of local lines: a run is consecutive
		# lines, so the range the report prints is the lines it printed.  Two
		# runs with the same verdict stay two blocks, because the lines the files
		# share between them are not part of what a re-sync discards.
		my $block;

		foreach my $line(@{ $run->[1] }) {
			my ($alike, $score) = _most_alike($line, \@master);
			my $kind = $score >= $ALIKE_ENOUGH ? 'replace' : 'discard';

			# Only a rewrite is given VWF's lines: a line VWF has
			# nothing like is not replaced by the nearest thing in the passage.
			my $replaces = $kind eq 'replace' && $alike ? $alike : undef;

			if($block && $block->{kind} eq $kind) {
				push @{ $block->{lines} }, $line;
				push @{ $block->{master} }, $replaces if($replaces);
				next;
			}

			$block = {
				lines  => [$line],
				kind   => $kind,
				master => $replaces ? [$replaces] : [],
			};
			push @blocks_of_passage, $block;
		}
	}

	# VWF's lines that will replace each block, in VWF's order and
	# without repeats: two local lines can be revisions of the same one.
	foreach my $block(@blocks_of_passage) {
		my %seen;
		$block->{master} = [sort { $a->[0] <=> $b->[0] }
			grep { !$seen{ $_->[0] }++ } @{ $block->{master} }];
	}

	push @{ $blocks }, @blocks_of_passage;

	return;
}

# The line of VWF's that reads most like this one, and how alike they
# are.  The most alike rather than the first, because a passage can hold several
# of VWF's lines and the one that will replace ours is the one it is a
# revision of.
sub _most_alike
{
	my ($line, $others) = @_;

	my ($alike, $best) = (undef, 0);

	foreach my $other(@{ $others }) {
		my $score = _affinity([$line], [$other]);
		next unless($score > $best);
		$alike = $other;
		$best = $score;
	}

	return ($alike, $best);
}

# How much two runs of lines read like the same code: the Dice coefficient over
# the words on either side, and 0 when there is nothing to compare them with --
# a run of bare braces has no words in it, and nothing to say about the other.
# Repeated words are counted as often as they occur, so a run with three
# arguments does not read as alike a run with one that happens to share a word.
sub _affinity
{
	my ($ours, $master) = @_;

	my @ours_words = map { _words($_->[1]) } @{ $ours };
	my @master_words = map { _words($_->[1]) } @{ $master };
	return 0 unless(@ours_words && @master_words);

	my %ours;
	$ours{$_}++ foreach @ours_words;

	my $shared = 0;
	foreach my $word(@master_words) {
		next unless($ours{$word});
		$ours{$word}--;
		$shared++;
	}

	return 2 * $shared / (scalar(@ours_words) + scalar(@master_words));
}

# The words of a line: identifiers and numbers, with punctuation, quotes and
# whitespace taken out.  A word is the unit a revision changes -- a name, an
# argument or a value -- where a bracket or a comma is not.
sub _words
{
	my $line = shift;
	return grep { length } split(/[^A-Za-z0-9_]+/, $line);
}

# The two files as runs of lines: [ 'both' | 'ours' | 'master', [lines] ].  The
# longest common subsequence of the two files' lines, because lines repeat: a
# bare "}" appears dozens of times in both, and looking a line up in a set would
# pair the wrong ones and call the rest an addition.  The subsequence pairs the
# most lines it can, so what is left over really is the difference between the
# two files.
#
# The runs are kept in the order the walk makes them, and a run of shared lines
# is one run, so that the caller can tell a passage whose local lines stand
# beside VWF's from one whose local lines stand alone.
sub _diff
{
	my ($ours, $master) = @_;

	my $n = scalar @{ $ours };
	my $m = scalar @{ $master };
	my $width = $m + 1;

	# Cell (i, j) of the table is the length of the longest common subsequence
	# of ours[i ..] and master[j ..], built from the end of both files back.
	# Cells past the end of either file read as zero, which is what the
	# recurrence wants there, so the table is a string of 16 bit cells rather
	# than a million scalars.
	my $lcs = '';

	for(my $i = $n - 1; $i >= 0; $i--) {
		my $row = $i * $width;
		my $below = $row + $width;

		for(my $j = $m - 1; $j >= 0; $j--) {
			my $length;

			if($ours->[$i][1] eq $master->[$j][1]) {
				$length = vec($lcs, ($below + $j + 1) * 16, 16) + 1;
			} else {
				my $down = vec($lcs, ($below + $j) * 16, 16);
				my $across = vec($lcs, ($row + $j + 1) * 16, 16);
				$length = $down > $across ? $down : $across;
			}

			vec($lcs, ($row + $j) * 16, 16) = $length;
		}
	}

	# Walk the table: a pair of lines that matches is part of the subsequence,
	# and a line taken from one file alone is one the other has not got.
	my @segments;
	my ($i, $j) = (0, 0);

	my $run = sub {
		my ($side, @lines) = @_;
		return unless(@lines);

		if(@segments && $segments[-1][0] eq $side) {
			push @{ $segments[-1][1] }, @lines;
		} else {
			push @segments, [$side, [@lines]];
		}

		return;
	};

	while($i < $n && $j < $m) {
		if($ours->[$i][1] eq $master->[$j][1]) {
			$run->('both', $ours->[$i]);
			$i++;
			$j++;
		} elsif(vec($lcs, (($i + 1) * $width + $j) * 16, 16)
			>= vec($lcs, ($i * $width + $j + 1) * 16, 16)) {
			$run->('ours', $ours->[$i++]);
		} else {
			$run->('master', $master->[$j++]);
		}
	}

	$run->('ours', @{ $ours }[$i .. $n - 1]) if($i < $n);
	$run->('master', @{ $master }[$j .. $m - 1]) if($j < $m);

	return @segments;
}
