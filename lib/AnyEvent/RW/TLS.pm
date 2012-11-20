package AnyEvent::RW::TLS;

use AnyEvent::RW::Kit;m{
use strict;
use warnings;
};
use Scalar::Util ();
use parent 'AnyEvent::RW';

use Errno qw(EAGAIN EINTR);
use AnyEvent::Util qw(WSAEWOULDBLOCK);

use Net::SSLeay qw(ERROR_SYSCALL ERROR_WANT_READ ST_OK);

sub MAX_READ_SIZE () { 128 * 1024 }

our $TLS_CTX;
sub TLS_CTX() {
	$TLS_CTX ||= do {
		require AnyEvent::TLS;
		AnyEvent::TLS->new();
	};
}

sub init {
	Scalar::Util::weaken( my $self = shift );
	my ($mode,$ctx) = @_;
	if (!$self->{tls}) {
		warn "create TLS";
		my $ctx ||= TLS_CTX();
		
		my $aetls = $ctx || TLS_CTX();
		#$self->{tls} = $aetls ->_get_session( $mode, $self, $host_to_verify ); # TODO
		$self->{tls} = my $tls = $aetls->_get_session( $mode, $self );
	
		Net::SSLeay::CTX_set_mode ($tls, 1|2);
	
		$self->{_rbio} = Net::SSLeay::BIO_new (Net::SSLeay::BIO_s_mem ());
		$self->{_wbio} = Net::SSLeay::BIO_new (Net::SSLeay::BIO_s_mem ());
	
		Net::SSLeay::BIO_write ($self->{_rbio}, $self->{rbuf});
		$self->{rbuf} = "";

		Net::SSLeay::set_bio ($tls, $self->{_rbio}, $self->{_wbio});
	} else {
		warn "$self already have tls";
	}
	$self->next::method();

	$self->_dotls();
	
	$self->_rw;
	#$self->_ww;
	return;
}


sub _tls_error {
	my ($self,$err) = @_;
	Carp::cluck "TLS Error: $err: ".Net::SSLeay::ERR_error_string($err) ;
}

sub _freetls {
	my $self = shift;
	return unless $self->{tls};
	
	$self->{tls_ctx} and
	$self->{tls_ctx}->_put_session (delete $self->{tls}) if $self->{tls} > 0;
	
	delete @$self{qw(_rbio _wbio _tls_wbuf _on_starttls)};
}

sub _dotls {
	Scalar::Util::weaken( my $self = shift );
	my $tmp;
	
	# Try write
		my $cur = $self->{wbuf};
		#warn "drain $self->{wsize} ($cur->{s} .. $self->{wlast}{s}) ".dumper $cur;
		while ( !exists $cur->{w} and exists $cur->{next} ) {
			$self->{wsize}--;
			$self->{wbuf} = $cur = $cur->{next};
		};
		if (exists $cur->{w}) {
			#warn "TLS drain $self->{wsize} ($cur->{s} .. $self->{wlast}{s}) ".dumper $cur;
			#warn "write to ssl ". dumper $self->{_tls_wbuf};
			while (exists $cur->{w} and ($tmp = Net::SSLeay::write ($self->{tls}, $cur->{w})) > 0) {
				#warn "written: $tmp";
				if (length $cur->{w} == $tmp) {
					delete $cur->{w};
					if ( exists $cur->{'next'} ) {
						$cur = $cur->{'next'};
						#warn "take next $cur->{s}";
						$self->{wbuf} = $cur;
						$self->{wsize}--;
					};
					
				} else {
					substr $cur->{w}, 0, $tmp, "";
				}
				#warn dumper $cur;
				#exit;
				#return;
			}
			#warn "after write: $tmp / $!";
			#last;
			# TODO!!!
			if (!$tmp) {
				$tmp = Net::SSLeay::get_error ($self->{tls}, $tmp);
				#warn ("TLS check error after write: $tmp ".ERROR_WANT_READ.'/'.ERROR_SYSCALL."/$!");
				return $self->_tls_error ($tmp) if $tmp != ERROR_WANT_READ and ($tmp != ERROR_SYSCALL || $!);
			}
		}
	
	# Try read
	
	while (defined ($tmp = Net::SSLeay::read ($self->{tls}))) {
		unless (length $tmp) {
			warn "read 0";
			$self->_freetls;
			delete $self->{_rw};
			$self->_error(Errno::EPIPE);
			#$self->{_eof} = 1;
			#$self->{on_read}(undef,"EOF");
			last;
		} else {
			$self->{on_read}(\$tmp);
		}
		#warn "received from ssl ". dumper $tmp;

#      $self->{_tls_rbuf} .= $tmp;
#      $self->_drain_rbuf;
		$self->{tls} or return; # tls session might have gone away in callback
	}
	
	#warn "check for error after w/r";
	
	$tmp = Net::SSLeay::get_error ($self->{tls}, -1);
	return $self->_tls_error ($tmp) if $tmp != ERROR_WANT_READ and ($tmp != ERROR_SYSCALL || $!);
	
	while (length (my $wr = Net::SSLeay::BIO_read ($self->{_wbio}))) {
		#warn "bio_read: ".dumper $tmp;
		
		#TODO: Now need to write
		if ($self->{_tls_wbuf}) {
			$self->{_tls_wbuf} .= $wr;
		} else {
			my $len = syswrite( $self->{fh}, $wr );
			if (defined $len) {
				if ($len != length $wr) {
					warn "Failed full write: $!";
					$self->{_tls_wbuf} = substr($wr,$len);
				}
			}
			elsif ($! == EAGAIN or $! == EINTR or $! == WSAEWOULDBLOCK) {
				$self->{_tls_wbuf} = $wr;
			}
			else {
					{
						local $! = 0+$!;
						warn "Shit happens: $!";
					}
					$self->_error();
					return;
			}
			if ($self->{_tls_wbuf}) {
				$self->{ww} = AE::io($self->{fh},1,sub {
					$self or return;
					my $len = syswrite( $self->{fh}, $self->{_tls_wbuf} );
					if (defined $len) {
						if ($len != length $self->{_tls_wbuf}) {
							substr($self->{_tls_wbuf},0,$len,'');
						} else {
							delete $self->{_tls_wbuf};
							delete $self->{ww};
						}
					}
					elsif ($! == EAGAIN or $! == EINTR or $! == WSAEWOULDBLOCK) {
						return;
					}
					else {
						{
							local $! = 0+$!;
							warn "Shit happens: $!";
						}
						$self->_error();
						return;
					}
				});
				last;
			}
		}
		
		#$self->{wbuf} .= $tmp;
		#$self->_drain_wbuf;
		$self->{tls} or return; # tls session might have gone away in callback
	}

#	$self->{_on_starttls}
#		and Net::SSLeay::state ($self->{tls}) == Net::SSLeay::ST_OK ()
#		and (delete $self->{_on_starttls})->($self, 1, "TLS/SSL connection established");
	return;
}


*_ww = \&_dotls;
sub _ww2 {
	warn "WW";
	shift->_dotls;
}

sub _rw {
	Scalar::Util::weaken( my $self = shift );
	return unless $self->{fh};
	$self->{rw} = AE::io( $self->{fh}, 0, my $cb = sub {
		local *__ANON__ = 'rw.cb';
		$self or return;
		my $buf;
		my $len;
		my $lsr;
		#warn "\n\n on_read... \n\n";
		#return;
		# TODO: bio_write?
		
		while ( $self and ( $len = sysread $self->{fh}, $buf, $self->{read_size}  ) ) {
			$self->{_activity} = $self->{_ractivity} = AE::now;
			$lsr = $len;
			#warn "read $len\n".dumper $buf;
			if ($len == $self->{read_size} and $self->{read_size} < $self->{max_read_size}) {
				$self->{read_size} *= 2;
				$self->{read_size} = $self->{max_read_size} || MAX_READ_SIZE
					if $self->{read_size} > ($self->{max_read_size} || MAX_READ_SIZE);
			}
			
			Net::SSLeay::BIO_write ($self->{_rbio}, $buf);
			$self->_dotls;
			#$self->{on_read}(\$buf);
		}
		#warn "lsr = $len/$!";
		return unless $self;
		if (defined $len) {
			#warn "EOF";
			$self->{_eof} = 1;
			{
				local $! = Errno::EPIPE;
				$self->_error();
			}
			#warn "Removing read watcher";
			delete $self->{rw};
		} else {
			if ($! == EAGAIN or $! == EINTR or $! == WSAEWOULDBLOCK) {
				#warn sysread $self->{fh},my $x,1;
				#warn "$! ($self->{read_size} / $lsr)";
				return;
			} else {
				warn "Shit happens: $!";
			}
		}
	} );
	$cb->();
}

sub _ww1 {
	return;
	Scalar::Util::weaken( my $self = shift );
	return unless $self->{fh};
	my $wr = sub {
		warn "can write ";
		$self or return;
		#warn "ww";
		delete $self->{ww};
		
=for rem
=cut
		
		my $cur = $self->{wbuf};
		#warn "drain $self->{wsize} ($cur->{s} .. $self->{wlast}{s}) ".dumper $cur;
		while ( !exists $cur->{w} and exists $cur->{next} ) {
			$self->{wsize}--;
			$self->{wbuf} = $cur = $cur->{next};
		};
		#warn "drain $self->{wsize} ($cur->{s} .. $self->{wlast}{s}) ".dumper $cur;
		while (exists $cur->{w}) {
			if (my $ref = ref $cur->{w}) {
				if ($ref eq 'CODE') {
					$cur->{w}->();
				} else {
					warn "Doesn't know how to process $ref";
				}
				delete $cur->{w};
				if ( exists $cur->{'next'} ) {
					$cur = $cur->{'next'};
					warn "take next $cur->{s}";
					$self->{wbuf} = $cur;
					$self->{wsize}--;
				};
				next;
			}
				$cur->{l} = length $cur->{w} unless exists $cur->{l};
				warn "call write $cur->{s}";
				
				while ((my $tmp = Net::SSLeay::write ($self->{tls}, $cur->{s})) > 0) {
					warn "written to ssl $tmp";
					substr $cur->{s}, 0, $tmp, "";
				}
				
		
				return;
				my $len = syswrite $self->{fh}, $cur->{w}, $cur->{l}, $cur->{o} || 0;
				if (defined $len) {
					$self->{_activity} = $self->{_wactivity} = AE::now;
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
					{
						local $! = 0+$!;
						warn "Shit happens: $!";
					}
					$self->_error();
					return;
				}
		}
	};
	$self->{ww} = &AE::io( $self->{fh}, 1, $wr);
	$wr->();
}

1;
