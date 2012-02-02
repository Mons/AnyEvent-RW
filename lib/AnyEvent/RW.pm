package AnyEvent::RW;

use 5.008008;
use common::sense 2;m{
use strict;
use warnings;
};
use Carp;

=head1 NAME

AnyEvent::RW - ...

=cut

our $VERSION = '0.01'; $VERSION = eval($VERSION);

=head1 SYNOPSIS

    package Sample;
    use AnyEvent::RW;

    ...

=head1 DESCRIPTION

    ...

=cut


=head1 METHODS

=over 4

=item ...()

...

=back

=cut

use uni::perl ':dumper';

use Errno qw(EAGAIN EINTR);
use AnyEvent::Util qw(WSAEWOULDBLOCK);

sub MAX_READ_SIZE () { 128 * 1024 }

sub new {
	my $pk = shift;
	my $self = bless {@_}, $pk;
	$self->init();
	$self;
}

sub init {
	my $self = shift;
	#warn dumper $self;
	
	$self->{wsize} = 1;
	$self->{wlast} = $self->{wbuf} = { s => 0 };
	
	$self->{read_size} ||= 4096;
	$self->{max_read_size} = $self->{read_size}
		if $self->{read_size} > ($self->{max_read_size} || MAX_READ_SIZE);
	
	&AnyEvent::Util::fh_nonblocking( $self->{fh}, 1 );
	binmode $self->{fh}, ':raw';
	
	$self->_rw;
}

sub _ww {
	my $self = shift;
	$self->{ww} = &AE::io( $self->{fh}, 1, sub {
		#warn "ww";
		delete $self->{ww};
		my $cur = $self->{wbuf};
		#warn "drain $self->{wsize} ($cur->{s} .. $self->{wlast}{s}) ".dumper $cur;
		while ( !exists $cur->{w} and exists $cur->{next} ) {
			$self->{wsize}--;
			$self->{wbuf} = $cur = $cur->{next};
		};
		#warn "drain $self->{wsize} ($cur->{s} .. $self->{wlast}{s}) ".dumper $cur;
		while (exists $cur->{w}) {
				$cur->{l} = length $cur->{w} unless exists $cur->{l};
				#warn "call write $cur->{s}";
				my $len = syswrite $self->{fh}, $cur->{w}, $cur->{l}, $cur->{o} || 0;
				if (defined $len) {
					$cur->{o} += $len;
					$cur->{l} -= $len;
					#warn "written $len, left $cur->{l}";#. dumper $cur;
					if ( $cur->{l} == 0 ) {
						#warn "go forward ".dumper $cur;
						delete $cur->{w};
						if ( exists $cur->{'next'} ) {
							$cur = $cur->{'next'};
							#warn "take next $cur->{s}";
							$self->{wbuf} = $cur;
							$self->{wsize}--;
						};
					}
				}
				elsif ( $!{EAGAIN} or $!{EINTR} or $!{WSAEWOULDBLOCK} ) {
					#warn "$!";
					return $self->_ww;
				}
				else {
					warn "Shit happens: $!";
					return;
				}
		}
	});
}
sub _rw {
	my $self = shift;
	$self->{rw} = AE::io( $self->{fh}, 0, sub {
		#warn "rw";
		my $buf;
		my $len;
		my $lsr;
		while ( ( $len = sysread $self->{fh}, $buf, $self->{read_size}  ) ) {
			$lsr = $len;
			if ($len == $self->{read_size} and $self->{read_size} < $self->{max_read_size}) {
				$self->{read_size} *= 2;
				$self->{read_size} = $self->{max_read_size} || MAX_READ_SIZE
					if $self->{read_size} > ($self->{max_read_size} || MAX_READ_SIZE);
			}
			$self->{read}(\$buf);
		}
		if (defined $len) {
			warn "EOF";
			$self->{end}("EOF");
			delete $self->{rw};
		} else {
			#if ($!{EAGAIN} or $!{EINTR} or $!{WSAEWOULDBLOCK}) {
			if ($! == EAGAIN or $! == EINTR or $! == WSAEWOULDBLOCK) {
				#warn "$! ($self->{read_size} / $lsr)";
				return;
			} else {
				warn "Shit happens: $!";
			}
		}
	} );
}

sub push_write {
	my $self = shift;
	ref $_[0] and die "Writing refs not supported yet";
	$self->{wsize}++;
	$self->{seq}++;
	my $l = { w => $_[0], s => $self->{seq} };
	$self->{wlast}{next} = $l;
	$self->{wlast} = $l;
	#warn dumper $self->{wbuf};
	$self->_ww;
}

=head1 AUTHOR

Mons Anderson, C<< <mons@cpan.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2012 Mons Anderson, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

=cut

1;
