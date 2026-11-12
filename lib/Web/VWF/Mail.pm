package Web::VWF::Mail;

# A message on its way to sendmail(1), signed with DKIM when the site has a
# key configured.
#
# The signature is made here, in the web process, rather than by a milter:
# the web user normally has no root access to install one, and a message
# handed to sendmail(1) never passes smtpd, so smtpd_milters - which only
# sees SMTP submissions - would not sign it in any case.
#
# Mail::DKIM is loaded at run time for the same reason it is only a
# recommendation: a site that does not sign, or one whose Mail::DKIM has gone
# missing, must still be able to send its contact form.  An unsigned message
# is a worse outcome than a signed one and a much better one than a lost
# enquiry, so every failure here falls back to sending unsigned.

use strict;
use warnings;

use Carp;
use Readonly;

our $VERSION = '0.01';

Readonly::Scalar my $DEFAULT_SENDMAIL => '/usr/sbin/sendmail';

# DKIM is defined over CRLF line endings.  Both hashes - the body hash and the
# header hash - are taken over the message as it would appear on the wire, so
# a bare LF anywhere in the message changes them and the signature fails at
# the receiver.
Readonly::Scalar my $CRLF => "\r\n";

=head1 NAME

Web::VWF::Mail - send mail through sendmail(1), DKIM signed when configured

=head1 SYNOPSIS

	my $mail = Web::VWF::Mail->new(
		from => 'no-reply@example.com',
		domain => 'example.com',
		selector => '202611',
		keyfile => '/home/site/dkim/202611.private',
	);

	$mail->print("To: someone\@example.com\n",
		"From: \"Example\" <no-reply\@example.com>\n",
		"Subject: hello\n\n",
		"Body\n");

	$mail->close or warn 'the message was not delivered';

=head1 DESCRIPTION

Buffers a message and, at L</close>, signs it with DKIM if the site has a
key and then pipes it to sendmail(1) with C<-t>.

Signing is skipped, and the message is sent unsigned, when C<domain>,
C<selector> or C<keyfile> is unset, when the key cannot be read, and when
Mail::DKIM is not installed or cannot produce a signature.  Each of those
cases warns, because an unsigned message from a site that expects to sign is
worth looking at - but it is still sent.

=head1 METHODS

=head2 new

Takes a hash or a hash reference of:

	from     - envelope sender, also given to sendmail -f (required)
	domain   - the domain to sign for; signing is skipped if unset
	selector - the DKIM selector, e.g. 202611; signing is skipped if unset
	keyfile  - path to the PEM private key; signing is skipped if unset
	sendmail - the program to run, defaulting to /usr/sbin/sendmail

The envelope sender matters as much as the header: sendmail fills in the web
user and this host when it is given nothing, and a receiving site is entitled
to reject that.

=head2 print

Appends text to the message.  The arguments are joined exactly as C<print>
would join them, so a caller can keep writing one C<print> statement per
header.

=head2 close

Signs the message, pipes it to sendmail(1), and returns true if sendmail
exited cleanly.  Calling it a second time returns the first result without
sending the message again, so it is safe in an END block.

=cut

sub new {
	my $class = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	croak('from is required') unless($args{'from'});

	my $self = {
		'from' => $args{'from'},
		'sendmail' => $args{'sendmail'} || $DEFAULT_SENDMAIL,
		'domain' => $args{'domain'},
		'selector' => $args{'selector'},
		'keyfile' => $args{'keyfile'},
		'buffer' => '',
		'status' => undef,
	};

	return bless $self, $class;
}

sub print {
	my $self = shift;

	$self->{'buffer'} .= join('', @_);

	return 1;
}

sub close {
	my $self = shift;

	# Undefined, not false, is the marker for "not sent yet": a failed send
	# has to be remembered as a failure rather than looked at again.
	return $self->{'status'} if(defined($self->{'status'}));

	my $message = $self->_sign($self->{'buffer'});

	open(my $fh, '|-', $self->{'sendmail'}, '-t', '-f', $self->{'from'}) or do {
		Carp::carp('Cannot run ', $self->{'sendmail'}, ': ', $!);
		return $self->{'status'} = 0;
	};

	print $fh $message;

	$self->{'status'} = close($fh) ? 1 : 0;

	return $self->{'status'};
}

# Return the message, with a DKIM-Signature line in front of it if it can be
# signed.  Private because a caller that signs part of a message and then
# sends it some other way would produce a signature over the wrong bytes.
sub _sign {
	my ($self, $message) = @_;

	my $domain = $self->{'domain'};
	my $selector = $self->{'selector'};
	my $keyfile = $self->{'keyfile'};

	my $signed = _crlf($message);

	return $signed unless($domain && $selector && $keyfile);

	unless(-r $keyfile) {
		warn "DKIM key $keyfile is not readable; sending unsigned\n";
		return $signed;
	}

	my $signer = eval {
		require Mail::DKIM::Signer;

		Mail::DKIM::Signer->new(
			Domain => $domain,
			Selector => $selector,
			KeyFile => $keyfile,
			Algorithm => 'rsa-sha256',
			# Both header and body relaxed: 'relaxed' alone would sign the
			# body with simple canonicalisation, so a message that picks up
			# a trailing newline on the way out would fail.
			Method => 'relaxed/relaxed',
		);
	};
	if(!$signer) {
		warn 'Cannot create DKIM signer: ', $@ || 'unknown error', "; sending unsigned\n";
		return $signed;
	}

	$signer->PRINT($signed);
	$signer->CLOSE;

	my @signatures = $signer->signatures();
	if(!@signatures) {
		warn "DKIM signing produced no signature; sending unsigned\n";
		return $signed;
	}

	return join('', map { $_->as_string() . $CRLF } @signatures) . $signed;
}

# sendmail(1) -t accepts CRLF, and DKIM requires it
sub _crlf {
	my $message = shift;

	$message =~ s/\r\n/\n/g;
	$message =~ s/\n/$CRLF/g;

	return $message;
}

1;
