#!/usr/bin/env perl

# The workflow steps, held to the rule that a failure cannot be swallowed.
#
# A step's status is the status of the last command in its script, so a step
# can be green whatever its checks did.  Three shapes do that: a C<||> handler
# that succeeds, as C<cpanm X || { cat build.log; }> does when the diagnostic
# is the last thing in it - the diagnostic is what makes it a pass; C<cpanm X
# || true>, which throws the status away outright, and is what
# C<perlcritic --severity 3 lib/ || true> did here, in a step that was already
# allowed to fail, so the findings were lost twice over; and C<cd cgi-bin &&
# perl -c page.fcgi> before another command, where the cd is exempt from the
# shell's C<-e> because it is not the last command of the C<&&> list, so a cd
# that failed is carried past.  This test reads every F<run:> block in
# F<.github/workflows> and holds it to all three.
#
# It judges the edges of a script - how a failing command is handled, and what
# the script ends with - rather than what the commands are, because which
# checks a workflow runs is the workflow's business.  A block whose shell is
# perl is not shell at all and is left to fail as the program it is, and a step
# that runs only once something has already failed (C<if: failure()>) is a
# diagnostic by design, since printing the log is its job.
#
# C<continue-on-error> is the one suppression these workflows make on purpose.
# It is allowed only for a step this test names and gives a reason for: a new
# one fails here until it is added to C<%JUSTIFIED>, and an entry that no
# longer matches a step fails too, so the list cannot rot into a licence.
#
# Before the workflows are read, the rules are run on scripts whose answer is
# known - a handler that exits non-zero, one that only prints, an C<&&> list at
# the end and in the middle - so a detector that has stopped catching what it
# was written for fails here rather than quietly passing the tree.

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Slurp qw(read_file);
use File::Spec;
use FindBin qw($Bin);
use Test::Most;

# Under prove -t, $Bin is tainted; detaint it before it reaches a file name.
my $root = do {
	my $dir = File::Spec->catdir($Bin, File::Spec->updir());
	$dir =~ /\A(.*)\z/s;
	abs_path($1);
};
my $workflows = File::Spec->catdir($root, '.github', 'workflows');

plan skip_all => "No workflows to read: $workflows" unless(-d $workflows);

# The steps allowed to tolerate a failure, and why.  Each key is the workflow
# file and the step's name, exactly as the YAML writes them.
my %JUSTIFIED = (
	'perl-ci.yml: Perl::Critic report (advisory)' => 'advisory: it reports the 178 severity-3 findings that predate the workflow, and gating on those would fail every run.  The severity-5 gate in the step above is the check.',
);

# Commands whose exit status says nothing about the checks that came before
# them.  A script that ends in one of these reports success whatever it found.
my %DIAGNOSTIC = map { $_ => 1 } qw(
	cat echo printf tail head ls more type true :
	Get-Content Write-Host Write-Output Write-Verbose
);

# A shell whose steps this test cannot judge: `shell: perl {0}` runs a Perl
# program, where `||` and `&&` are operators with their own meaning.
sub is_shell {
	my $shell = shift;
	return 0 if($shell =~ /\bperl\b/);
	return 1;
}

# Commands whose status makes a step fail, as written at the end of a ||
# handler: `exit`, `exit 1`, cmd's `exit /b 1`, `false`, or - inside a shell
# function, which is where the lint checks report from - `return 1`.  An `exit`
# with no argument exits with the status that reached it, which is the
# failure.
sub exits_nonzero
{
	my $text = shift;
	return 1 if($text =~ /\A\s*(?:false|(?:exit|return)(?:\s+(?:\/b\s+)?[1-9]\d*)?)\s*;?\s*\z/);
	return 1 if($text =~ /\A\s*[({].*\b(?:exit|return)(?:\s+(?:\/b\s+)?[1-9]\d*)?\b.*\z/s);
	return 0;
}

# Everything the rules have to say about one run: block.
sub masked_failures
{
	my ($script, $shell) = @_;

	my @lines = split(/\r?\n/, $script);
	my @findings;

	# The lines that are commands: a comment line is not one, and a blank line
	# neither, so a script cannot be said to end in a comment.
	my @command_lines = grep { $lines[$_] =~ /\S/ && $lines[$_] !~ /^\s*#/ } 0 .. $#lines;
	my $last_index = $command_lines[-1];
	my $last = defined($last_index) ? $lines[$last_index] : undef;

	for(my $i = 0; $i <= $#lines; $i++) {
		my $line = $lines[$i];
		next if($line !~ /\S/ or $line =~ /^\s*#/);

		# Only in a shell: in a Perl or PowerShell block `||` is a program's
		# own operator, and judging it as a shell handler would be wrong.
		if(is_shell($shell) && $line =~ /\|\|(.*)\z/) {
			my $handler = $1;
			# A handler written across several lines is gathered up so that
			# its exit, which is on the last of them, is seen.
			if($handler =~ /\A\s*[({]\s*\z/) {
				my $depth = ($handler =~ tr/{([//);
				my $j = $i + 1;
				while($j <= $#lines and $depth > 0) {
					$depth += ($lines[$j] =~ tr/{([//);
					$depth -= ($lines[$j] =~ tr/})]//);
					$handler .= "\n$lines[$j]";
					$j++;
				}
			}

			unless(exits_nonzero($handler)) {
				if($handler =~ /\A\s*(?:true|:|\/bin\/true|exit\s+0)\s*;?\s*\z/) {
					push @findings, 'line ' . ($i + 1)
						. ': a || handler that always succeeds throws the failure away (' . trim($line) . ')';
				} else {
					push @findings, 'line ' . ($i + 1) . ": the || handler does not exit non-zero, so its own success becomes the step's ("
						. trim($line) . ')';
				}
			}
		}

		# `A && B` is exempt from the shell's -e except for its last command,
		# so mid-script it carries a failure at A past the rest of the script.
		# Guarded with a || that exits non-zero it is fine, and as the last
		# command of the script its status is the step's whatever it is.
		if(is_shell($shell) && $line =~ /&&/ && defined($last_index) && $i != $last_index && $line !~ /\|\|/) {
			push @findings, 'line ' . ($i + 1) . ": an && list before the last command is exempt from the shell's -e ("
				. trim($line) . ')';
		}
	}

	if(is_shell($shell) && defined($last)) {
		if($last =~ /\A\s*exit\s+0\s*;?\s*\z/) {
			push @findings, 'the script ends by exiting 0, whatever the commands before it returned';
		} elsif($last =~ /\A\s*(?:sudo\s+)?([\w.\/-]+)/ && $DIAGNOSTIC{$1}) {
			push @findings, "the script ends in $1, a diagnostic whose success becomes the step's (" . trim($last) . ')';
		}
	}

	if(is_shell($shell) && $script =~ /^\s*set\s+\+[eo]/m) {
		push @findings, 'the script turns the shell\'s -e back off';
	}

	return @findings;
}

sub trim
{
	my $text = shift;
	$text =~ s/\A\s+//;
	$text =~ s/\s+\z//;
	return $text;
}

sub indent_of
{
	my $line = shift;
	$line =~ /\A(\s*)/;
	return length($1);
}

# The steps of a workflow, each with the shell it runs, whether it tolerates a
# failure, and the scripts it runs.  Hand-read rather than parsed with a YAML
# module: the files are this repository's own and live in one style, and the
# count of run: blocks read is checked against the count in the text, so a
# block this misses fails the test instead of going unexamined.
sub read_steps
{
	my $path = shift;

	my @lines = split(/\r?\n/, read_file($path));
	my @steps;
	my $step;

	for(my $i = 0; $i <= $#lines; $i++) {
		my $line = $lines[$i];

		if($line =~ /\A\s*-\s+(?:name|uses):/) {
			push @steps, $step if($step);
			$step = { name => '(unnamed step)', shell => 'bash', condition => '', continue_on_error => 0, runs => [] };
			$step->{name} = $1 if($line =~ /\A\s*-\s+name:\s*(.+?)\s*\z/);
		}
		next unless($step);

		$step->{shell} = $1 if($line =~ /\A\s+shell:\s*(.+?)\s*\z/);
		$step->{condition} = $1 if($line =~ /\A\s+if:\s*(.+?)\s*\z/);
		$step->{continue_on_error} = 1 if($line =~ /\A\s+continue-on-error:\s*true\s*\z/);

		next unless($line =~ /\A(\s+)run:\s*(.*?)\s*\z/);

		my $indent = length($1);
		my $value = $2;
		# `run: |   # the step` is a block scalar with a comment on it, not a
		# command that happens to begin with a pipe.
		$value =~ s/\s+#.*\z//;
		if($value =~ /\A[|>][-+]?\z/) {
			my @body;
			my $j = $i + 1;
			while($j <= $#lines) {
				last if($lines[$j] =~ /\S/ && indent_of($lines[$j]) <= $indent);
				push @body, $lines[$j];
				$j++;
			}

			# A block scalar is de-indented by its shallowest non-blank line,
			# which is the indentation YAML gives it.
			my $shallowest;
			foreach my $body_line (@body) {
				next if($body_line !~ /\S/);
				my $depth = indent_of($body_line);
				$shallowest = $depth if(!defined($shallowest) || $depth < $shallowest);
			}
			$shallowest = 0 unless(defined($shallowest));

			push @{$step->{runs}}, join("\n", map { /\S/ ? substr($_, $shallowest) : '' } @body);
			$i = $j - 1;
		} else {
			push @{$step->{runs}}, $value;
		}
	}

	push @steps, $step if($step);

	return \@steps;
}

# A step that runs once something has failed is a diagnostic by design: the
# log it prints is the point, and the step that failed has already failed.
sub is_diagnostic_step
{
	my $step = shift;
	return 1 if($step->{condition} =~ /(?:failure|always|cancelled)\(\)/);
	return 0;
}

my @cases = (
	[ 'a || handler that exits non-zero', 'cpanm X || { cat build.log; exit 1; }', 0 ],
	[ 'a || handler that only prints the log', 'cpanm X || { cat build.log; }', 1 ],
	[ 'a || handler that prints the log inline', 'cpanm X || cat build.log', 1 ],
	[ 'a || handler that always succeeds', 'cpanm X || true', 1 ],
	[ 'a || handler that exits 0', 'cpanm X || exit 0', 1 ],
	[ 'a || handler that exits with the status', 'cpanm X || exit', 0 ],
	[ 'a || handler that fails outright', 'cpanm X || false', 0 ],
	[ 'a script that ends in its check', "prove -l t/\nperl -c page.fcgi ''", 0 ],
	[ 'a script that ends in a diagnostic', "prove -l t/\ncat /tmp/vwf.log", 1 ],
	[ 'a diagnostic that is not the last command', "prove -l t/\ncat /tmp/vwf.log\nprove x", 0 ],
	[ 'a script that ends by exiting 0', "prove -l t/\nexit 0", 1 ],
	[ 'an && list before the last command', "cd cgi-bin && perl -c page.fcgi\nprove x", 1 ],
	[ 'an && list as the last command', "prove x\ncd cgi-bin && perl -c page.fcgi", 0 ],
	[ 'an && list guarded by an exit', "cd cgi-bin && perl -c page.fcgi || exit 1\nprove x", 0 ],
	[ 'a script that turns -e off', "set +e\nprove x", 1 ],
);

foreach my $case (@cases) {
	my ($title, $script, $expected) = @{$case};
	my @findings = masked_failures($script, 'bash');
	is(scalar(@findings), $expected, "the rules judge $title as they should")
		or diag(explain(\@findings));
}

# A block whose shell is perl is not shell, so neither a || operator nor an
# && operator in it is judged by these rules: they are Perl's, not the shell's.
is(scalar(masked_failures("my \$p = param('page') || 'index';\nprint \"\$p\\n\";\nmy \$ok = f() && g();", 'perl {0}')), 0,
	'a perl block is not read as shell');

# The suppressions are checked, and the checking is checked: a step that
# tolerates a failure without a reason is a finding.
{
	my $unjustified = sub {
		my ($scanned, $table) = @_;
		$table //= \%JUSTIFIED;
		return [ map { join(': ', $_->{file}, $_->{name}) }
			grep { $_->{continue_on_error} && !$table->{join(': ', $_->{file}, $_->{name})} } @{$scanned} ];
	};

	my $fixture = [
		{ file => 'example.yml', name => 'a step that tolerates a failure', continue_on_error => 1 },
		{ file => 'example.yml', name => 'a step that does not', continue_on_error => 0 },
	];
	is_deeply($unjustified->($fixture), ['example.yml: a step that tolerates a failure'],
		'a continue-on-error without a reason is a finding');

	is_deeply(
		$unjustified->([ { file => 'example.yml', name => 'a step that tolerates a failure', continue_on_error => 1 } ],
			{ 'example.yml: a step that tolerates a failure' => 'because this test says so' }),
		[], 'a continue-on-error this test names and explains is allowed');

	my $scanned;
	foreach my $path (glob(File::Spec->catfile($workflows, '*.yml'))) {
		(my $file = $path) =~ s{.*/}{};
		foreach my $step (@{ read_steps($path) }) {
			push @{$scanned}, { %{$step}, file => $file };
		}
	}
	is_deeply($unjustified->($scanned), [], 'every continue-on-error in the workflows is justified here');

	my %named = map { join(': ', $_->{file}, $_->{name}) => 1 } grep { $_->{continue_on_error} } @{$scanned};
	is_deeply([ sort grep { !$named{$_} } keys %JUSTIFIED ], [],
		'every step named in this test still tolerates a failure, so no reason is left over');
}

# The workflows themselves.
{
	my @workflows = sort glob(File::Spec->catfile($workflows, '*.yml'));
	ok(scalar(@workflows), 'there are workflows to hold to the rule')
		or BAIL_OUT("Nothing under $workflows");

	foreach my $path (@workflows) {
		(my $file = $path) =~ s{.*/}{};
		my $text = read_file($path);
		my $steps = read_steps($path);

		my $declared = () = $text =~ /^\s+run:/mg;
		my $read = 0;
		$read += scalar(@{$_->{runs}}) foreach @{$steps};
		is($read, $declared, "$file: every run: block in the file was read, so none goes unexamined");

		my @findings;
		foreach my $step (@{$steps}) {
			next if(is_diagnostic_step($step));
			foreach my $script (@{$step->{runs}}) {
				push @findings, map { "step '$step->{name}': $_" } masked_failures($script, $step->{shell});
			}
		}

		is_deeply(\@findings, [], "$file: no step lets a diagnostic or an && list hide a failing command")
			or diag(explain(\@findings));

		note("$file: " . scalar(@{$steps}) . ' steps, ' . $read . ' run: ' . ($read == 1 ? 'block' : 'blocks'));
	}
}

done_testing();
