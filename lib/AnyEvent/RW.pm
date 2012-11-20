package AnyEvent::RW;

use 5.008008;
use Scalar::Util ();
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

#use uni::perl ':dumper';

use Errno qw(EAGAIN EINTR);
use AnyEvent::Util qw(WSAEWOULDBLOCK);

sub MAX_READ_SIZE () { 128 * 1024 }

sub new {
	my $pk = shift;
	my $self = bless {@_}, $pk;
	$self->{debug} //= 1;
	$self->{for} = " (".fileno($self->{fh}).") @{[ (caller)[1,2] ]}" if $self->{debug};
	if ($self->{debug}) {
		warn sprintf "%08x creating AE::RW for %s\n", int $self, $self->{for};
	}
	$self->init();
	$self;
}

sub upgrade {
	my $self = shift;
	my $class = shift;
	$class =~ s{^\+}{} or $class = "AnyEvent::RW::$class";
	croak "$class is not a subclass of ".ref($self) if !UNIVERSAL::isa($class,ref($self));
	bless $self,$class;
	$self->init(@_);
}

sub init {
	Scalar::Util::weaken( my $self = shift );
	#warn dumper $self;
	
	$self->{debug} //= 1;
	$self->{wsize} = 1;
	$self->{wlast} = $self->{wbuf} = { s => 0 };
	
	$self->{read_size} ||= 4096;
	$self->{max_read_size} = $self->{read_size}
		if $self->{read_size} > ($self->{max_read_size} || MAX_READ_SIZE);
	
	&AnyEvent::Util::fh_nonblocking( $self->{fh}, 1 );
	binmode $self->{fh}, ':raw';
	
	# \Compat
	if (exists $self->{on_timeout} or exists $self->{on_eof} or exists $self->{on_error}) {
		my $end = delete $self->{on_end};
		$self->{on_end} = sub {
			$self or return;
			# on_timeout could be undestructive, so leave it as in AE::Handle
			#return $self->{on_timeout}() if $! == Errno::ETIMEDOUT and exists $self->{on_timeout};
			return $self->{on_eof}() if $! == Errno::EPIPE and exists $self->{on_eof};
			return $self->{on_error}() if $! > 0 and exists $self->{on_error};
			return $self->{on_end}( $! > 0 ? "$!" : ());
		};
	}
	# /Compat
	
	
	$self->{_activity}  =
	$self->{_ractivity} =
	$self->{_wactivity} = AE::now;
	
	$self->timeout   (delete $self->{timeout}  ) if $self->{timeout};
	$self->rtimeout  (delete $self->{rtimeout} ) if $self->{rtimeout};
	$self->wtimeout  (delete $self->{wtimeout} ) if $self->{wtimeout};
	
	$self->_rw if $self->{on_read};
}

{ no strict 'refs';

for my $dir ("", "r", "w") {
   my $timeout    = "${dir}timeout";
   my $tw         = "_${dir}tw";
   my $on_timeout = "on_${dir}timeout";
   my $activity   = "_${dir}activity";
   my $cb;

   *$on_timeout = sub {
      $_[0]{$on_timeout} = $_[1];
   };

   *$timeout = sub {
      my ($self, $new_value) = @_;

      $new_value >= 0
         or Carp::croak "AnyEvent::Handle->$timeout called with negative timeout ($new_value), caught";

      $self->{$timeout} = $new_value;
      delete $self->{$tw}; &$cb;
   };

   *{"${dir}timeout_reset"} = sub {
      $_[0]{$activity} = AE::now;
   };

   # main workhorse:
   # reset the timeout watcher, as neccessary
   # also check for time-outs
   $cb = sub {
      my ($self) = @_;

      if ($self->{$timeout} and $self->{fh}) {
         my $NOW = AE::now;

         # when would the timeout trigger?
         my $after = $self->{$activity} + $self->{$timeout} - $NOW;

         # now or in the past already?
         if ($after <= 0) {
            $self->{$activity} = $NOW;

            if ($self->{$on_timeout}) {
               $self->{$on_timeout}($self, $self->{$timeout} - $after);
            } else {
               {
                  local $! = Errno::ETIMEDOUT;
                  $self->_error (Errno::ETIMEDOUT);
               }
            }

            # callback could have changed timeout value, optimise
            return unless $self->{$timeout};

            # calculate new after
            $after = $self->{$timeout};
         }

         Scalar::Util::weaken $self;
         return unless $self; # ->error could have destroyed $self

         $self->{$tw} ||= AE::timer $after, 0, sub {
            delete $self->{$tw};
            $cb->($self);
         };
      } else {
         delete $self->{$tw};
      }
   }
}
}

sub _ww {
	Scalar::Util::weaken( my $self = shift );
	return unless $self->{fh};
	my $wr = sub {
		#warn "can write";
		$self or return;
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
				#warn "call write $cur->{s}";
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
sub _rw {
	Scalar::Util::weaken( my $self = shift );
	return unless $self->{fh};
	$self->{rw} = AE::io( $self->{fh}, 0, sub {
		local *__ANON__ = 'rw.cb';
		$self or return;
		my $buf;
		my $len;
		my $lsr;
		#warn "read...";
		no warnings 'unopened';
		while ( $self and ( $len = sysread $self->{fh}, $buf, $self->{read_size}  ) ) {
			$self->{_activity} = $self->{_ractivity} = AE::now;
			$lsr = $len;
			#warn "read $len";
			if ($len == $self->{read_size} and $self->{read_size} < $self->{max_read_size}) {
				$self->{read_size} *= 2;
				$self->{read_size} = $self->{max_read_size} || MAX_READ_SIZE
					if $self->{read_size} > ($self->{max_read_size} || MAX_READ_SIZE);
			}
			$self->{on_read}(\$buf);
			$self->{on_read} or return delete $self->{rw};
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
			delete $self->{rw};
		} else {
			#if ($!{EAGAIN} or $!{EINTR} or $!{WSAEWOULDBLOCK}) {
			if ($! == EAGAIN or $! == EINTR or $! == WSAEWOULDBLOCK) {
				#warn sysread $self->{fh},my $x,1;
				#warn "$! ($self->{read_size} / $lsr)";
				return;
			} else {
				warn "Shit happens: $!";
				{
					local $! = Errno::EPIPE;
					$self->_error();
				}
				delete $self->{rw};
			}
		}
	} );
}

sub _error {
	my $self = shift;
	my $err = @_ ? $_[0] : 0+$!;
	delete $self->{fh};
	delete $self->{rw};
	delete $self->{ww};
	if (exists $self->{on_end}) {
		$self->{on_end}("$!");
	}
	elsif ( exists $self->{on_read}) {
		$self->{on_read}(undef, "$!");
	}
	else {
		local $! = $err;
		warn "error: $! (@_) @{[ (caller)[1,2] ]}";
		
	}
}

sub AnyEvent::RW::destroyed::AUTOLOAD {}
sub AnyEvent::RW::destroyed::destroyed { 1 }

sub destroy {
	my ($self) = @_;
	$self->DESTROY;
	%$self = ();
	bless $self, "AnyEvent::RW::destroyed";
}

sub DESTROY {
	my $self = shift;
	$self->{on_destroy} and $self->{on_destroy}();
	#warn sprintf "%08x (%d) Destroying AE::RW ($self->{for}) %s", int($self), fileno $self->{fh}, dumper $self->{wbuf} if $self->{debug};
	warn sprintf "%08x (%d) Destroying AE::RW ($self->{for}) %s", int($self), $self->{fh} ? fileno $self->{fh} : -1, "@{[ (caller)[1,2] ]}" if $self->{debug};
	%$self = ();
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

sub push_sub {
	my $self = shift;
	ref $_[0] or die "Need sub";
	$self->{wsize}++;
	$self->{seq}++;
	my $l = { w => $_[0], s => $self->{seq} };
	$self->{wlast}{next} = $l;
	$self->{wlast} = $l;
	#warn dumper $self->{wbuf};
	$self->_ww;
}

sub push_close {
	my $self = shift;
	$self->push_sub(sub {
		close $self->{fh};
		$self->destroy;
	});
}

sub starttls {
	my ($self, $mode, $ctx) = @_;
	require AnyEvent::RW::TLS;
	$self->upgrade('TLS', $mode, $ctx);
=for re
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
	
=cut
	#$self->{_on_starttls} = sub { $_[0]{on_starttls}(@_) }
	#	if $self->{on_starttls};
	
	

	#&_dotls; # need to trigger the initial handshake
	#$self->start_read; # make sure we actually do read
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
