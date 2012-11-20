package AnyEvent::RW::RQ;

use AnyEvent::RW::Kit;m{
use strict;
use warnings;
};
use parent 'AnyEvent::RW';

sub init {
	Scalar::Util::weaken( my $self = shift );
	$self->{on_read} and die "Don't set read callback";
	$self->{on_read} = sub {
		$self or return;
		#warn "RW.RQ on_read";
		local *__ANON__ = 'read.cb';
		$self->{rbuf} .= ${$_[0]};
		if (@{ $self->{rq} }) {
			$self->_drain_r;
		} else {
			if (length $self->{rbuf} > 1024*256) {
				warn "no more readers and big enough buffer\n";
			}
		}
	};
	$self->next::method(@_);
	return;
}

sub push_read {
	my $self = shift;
	unshift @_, 'regex' if UNIVERSAL::isa( $_[0], 'Regexp' );
	push @{ $self->{rq} }, [@_];
	$self->_drain_r if length $self->{rbuf};
	return;
}

sub unshift_read {
	my $self = shift;
	unshift @_, 'regex' if UNIVERSAL::isa( $_[0], 'Regexp' );
	unshift @{ $self->{rq} }, [@_];
	$self->_drain_r if length $self->{rbuf};
	return;
}

sub _drain_r {
	Scalar::Util::weaken( my $self = shift );
	$self or return;
	#warn "got rbuf $self->{rbuf}";
	return if $self->{_skip_drain_rbuf};
	local $self->{_skip_drain_rbuf} = 1;
	my $i;
	#warn "drain ".dumper $self->{rbuf};
	LOOP:
	while (do{ undef $i; !!@{ $self->{rq} } }) {
		my $len = length $self->{rbuf};
		#warn "loop [@{ $self->{rq} }]";
		if ($i = shift @{ $self->{rq} }) {
			given ($i->[0]) {
				when ('line') {
					#warn "parse as line";
					if ((my $idx = index( $self->{rbuf}, "\n" )) > -1) {
						my $s = substr($self->{rbuf},0,$idx+1,'');
						#warn dumper $s;
						my $nl = substr($s,-2,1) eq "\015" ? substr( $s,-2,2,'' ) : substr($s,-1,1,'');
						#warn "index match $idx ".dumper $nl;
						$i->[1]( $self, $s, $nl );
						next LOOP;
					} else {
						last LOOP;
					}
				}
				when ('regex') {
					#warn "parse as regex $i->[1] ";#.dumper( $self->{rbuf} );
					if ( $self->{rbuf} =~ $i->[1] ) {
						#warn "regex match $+[0] ";
						$i->[2]( $self, substr($self->{rbuf},0,$+[0],'') );
						next LOOP;
					} else {
						last LOOP;
					}
				}
				when ('chunk') {
					#warn "parse as chunk $i->[1]";
					if ( $i->[1] < $len ) {
						$i->[2]( $self, substr($self->{rbuf},0,$i->[1],'') );
						next LOOP;
					} else {
						last LOOP;
					}
				}
				when ('all') {
					#warn "pass all (eof=$self->{_eof})";
					if ($len > 0) {
						my $rr = delete $self->{rbuf};
						$i->[1]( $self, $rr );
						next LOOP;
					} else {
						warn "no data for $_";
						last LOOP;
					}
				}
				default {
					die "Unknown : $_";
					last LOOP;
				}
				#$self->_error( Errno::EPIPE ) if $self->{_eof};
				#last LOOP;
			}
		}
	}
	if ($i) {
		#warn "need more data for [@{[ @$i ]}]";
		unshift @{ $self->{rq} },$i;
	} else {
		#warn "no more readers";
		#delete $self->{rw};
	}
	return;
}

sub _error {
	my $self = shift;
	my $errno = $!;
	local $self->{on_read} = sub {};
	$self->next::method(@_);
	while (my $i = shift @{ $self->{rq} }) {
		local $! = $errno;
		$i->[-1]->(undef, "$!");
	}
}

1;
