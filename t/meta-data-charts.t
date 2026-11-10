#!/usr/bin/env perl

# Smoke test for the meta_data charts, without a browser.
#
# "Headless" here means no DOM and no JavaScript engine: the CI container is a
# bare perl, so there is nothing to run the inline D3 scripts.  What a browser
# needs before it can draw is checked instead - every one of the five charts
# must render its own SVG and carry at least one data point.  A chart that
# loses its id, or whose data comes back empty, is a blank frame in the browser
# and fails here.
#
# The other way a chart ends up blank - two snippets both declaring
# "const data", so the second script throws - is covered by the script-scoping
# checks in t/function.t.

use strict;
use warnings;

use Test::Most;
use Test::Mockingbird;

use File::Spec;
use FindBin qw($Bin);
use JSON::MaybeXS qw(decode_json);
use POSIX qw(strftime);
use Readonly;

use lib File::Spec->catdir($Bin, File::Spec->updir(), 'lib');

use Web::VWF::Display;
use Web::VWF::Display::meta_data;

Readonly my @CHARTS => qw(browser_chart status_chart rate_chart latency_chart slow_chart);

# ---------------------------------------------------------------------------
# Stand-ins for the objects the page is handed at run time
# ---------------------------------------------------------------------------

package Local::Info {
	sub new { return bless { domain_name => 'example.com' }, shift }
	sub domain_name { return $_[0]->{'domain_name'} }
}

# The access log, in the shape Web::VWF::Data::vwf_log gives the page
package Local::VwfLog {
	sub new { my ($class, @rows) = @_; return bless { rows => \@rows }, $class }
	sub selectall_array { return @{$_[0]->{'rows'}} }
	sub type {
		my ($self, $args) = @_;
		return grep { ref($_) eq 'HASH' && ($_->{'type'} // '') eq $args->{'type'} } @{$self->{'rows'}};
	}
	sub http_code {
		return map { $_->{'http_code'} } grep { ref($_) eq 'HASH' } @{$_[0]->{'rows'}};
	}
}

package main;

# How many marks the browser will draw from a chart snippet: one per slice or
# bar, and one per point for a multi-series line chart.  Returns 0 when the
# snippet has no data at all, which is the failure this test is looking for.
sub chart_points
{
	my ($html) = @_;

	my ($json) = $html =~ /(?:const|var|let)\s+(?:data|series)\s*=\s*(\[.*?\]);/s;
	return 0 unless defined($json);

	my $data = decode_json($json);
	my $points = 0;
	foreach my $item (@{$data}) {
		if(ref($item) eq 'HASH' && ref($item->{'data'}) eq 'ARRAY') {
			$points += scalar(@{$item->{'data'}});
		} else {
			$points++;
		}
	}

	return $points;
}

my $stamp = sub { strftime('%Y-%m-%d %H:%M:%S', localtime(CORE::time() - shift)) };
my $when = $stamp->(60);

# Enough traffic for all five charts: every browser type, several status
# codes, two templates with enough samples to rank, and plausible durations
my @rows = (
	(map { { time => $when, ip => "10.0.0.$_", type => 'web', http_code => 200, duration_ms => 120, template => '/srv/templates/web/index.tmpl' } } 1 .. 6),
	(map { { time => $when, ip => "10.0.1.$_", type => 'mobile', http_code => 404, duration_ms => 400, template => '/srv/templates/web/meta_data.tmpl' } } 1 .. 6),
	{ time => $when, ip => '10.0.2.1', type => 'search', http_code => 500, duration_ms => 50 },
	{ time => $when, ip => '10.0.2.2', type => 'robot', http_code => 200, duration_ms => 50 },
	{ time => $when, ip => '10.0.2.3', type => 'ai', http_code => 200, duration_ms => 50 },
);

my $display = bless {
	info => Local::Info->new(),
	config => {},
}, 'Web::VWF::Display::meta_data';

my %chart;
mock 'Web::VWF::Display::html' => sub { %chart = %{$_[1]}; return 'page' };
mock 'Web::VWF::Display::meta_data::get_server_metrics' => sub {
	return { cpu_count => 1, cpu_type => 'test', disk_used_pct => 1, memory_used_pct => 1 };
};

is($display->html(vwf_log => Local::VwfLog->new(@rows)), 'page', 'meta_data renders');

my $page = join("\n", map { $chart{$_} // '' } @CHARTS);

foreach my $id (@CHARTS) {
	my $html = $chart{$id};
	ok(defined($html) && length($html), "$id rendered");

	# An SVG with the right id is what the snippet's script selects; without
	# it d3.select() finds nothing and the chart is blank
	my $svgs = () = $page =~ /<svg id="\Q$id\E"/g;
	is($svgs, 1, "exactly one $id svg");

	my $points = chart_points($html // '');
	cmp_ok($points, '>=', 1, "$id has data to draw ($points point(s))");
}

# An empty log must give placeholders, never a frame with nothing in it
%chart = ();
$display->html(vwf_log => Local::VwfLog->new());
foreach my $id (@CHARTS) {
	unlike($chart{$id} // '', qr/<svg/, "$id is not rendered as a blank frame");
}

restore_all();

done_testing();
