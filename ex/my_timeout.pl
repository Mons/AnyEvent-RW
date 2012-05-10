#!/usr/bin/env perl

use 5.010;
use lib::abs '..';


use AnyEvent::RW::RQ;

use uni::perl ':dumper';

use Scalar::Util 'weaken';
use AnyEvent::Impl::Perl;
use AE;
use AnyEvent::Socket;
use Time::HiRes 'time';
#use Devel::Refcount 'refcount';
$| = 1;

my $recv;
sub M () { 1024*1024 }
my $port = 19999;

tcp_server 0, $port, sub {
	my $fh = shift;
	use AnyEvent::Handle;
	my $r;$r = AnyEvent::Handle->new(
		fh => $fh,
		debug => 0,
		on_error => sub { shift->destroy },
	);
	$r->{x} = sub { $r };
	$r->push_read( line => sub {
		shift;
		given ($_[0]) {
			when (/timeout (\d+)/) {
				say "timeout $1";
				my $t;$t = AE::timer $1,0, sub {
					undef $t;
					warn "Fire";
					$r->push_write("ready\n");
					$r->push_write(sub { $r->destroy });
				};
			}
			default {
				warn dumper \@_;
			}
		}
	} );
};

use Test::More;
$SIG{ALRM} = sub { confess 1 };
alarm 10;


sub test (&) {
	my $code = shift;
	my $cv = AE::cv;
	my $w;
	my $r;
	tcp_connect 0, $port, sub {
		$r = $code->(@_,$cv);
		ok $r, 'test returned $r';
		weaken($w = $r);
	};
	$cv->recv;
	undef $r;
	ok !$w, '$r destroyed '."$w";
}

test {
	my $cv = pop;
	my $r = AnyEvent::RW::RQ->new(
		fh => $_[0],
		timeout => 1,
	);
	$r->push_write("timeout 0.1\n");
	$r->push_read(line => sub {
		is $_[0], "ready", "received ready" or diag $_[1];
		undef $r;
		$cv->send;
	});
	return $r;
};

test {
	my $cv = pop;
	my $r = AnyEvent::RW::RQ->new(
		fh => $_[0],
		timeout => 0.1,
	);
	$r->push_write("timeout 1\n");
	$r->push_read(line => sub {
		ok !$_[0], "no ready";
		is 0+$!, Errno::ETIMEDOUT, "have errno";
		is "$!", $_[1], "have error arg";
		undef $r;
		$cv->send;
	});
	return $r;
};

test {
	my $cv = pop;
	my $r = AnyEvent::RW::RQ->new(
		fh => $_[0],
		timeout => 0.1,
		on_end => sub {
			is 0+$!, Errno::ETIMEDOUT, "have errno in on_end";
			is "$!", $_[0], "have error arg in on_end";
		},
	);
	$r->push_write("timeout 1\n");
	$r->push_read(line => sub {
		ok !$_[0], "no ready";
		is 0+$!, Errno::ETIMEDOUT, "have errno";
		is "$!", $_[1], "have error arg";
		undef $r;
		$cv->send;
	});
	return $r;
};

test {
	my $cv = pop;
	my $r = AnyEvent::RW::RQ->new(
		fh => $_[0],
		timeout => 0.1,
		on_error => sub {
			is 0+$!, Errno::ETIMEDOUT, "have errno in on_error";
			is "$!", $_[0], "have error arg in on_error";
		},
		on_end => sub {
			is 0+$!, Errno::ETIMEDOUT, "have errno in on_end";
			is "$!", $_[0], "have error arg in on_end";
		},
	);
	$r->push_write("timeout 1\n");
	$r->push_read(line => sub {
		ok !$_[0], "no ready";
		is 0+$!, Errno::ETIMEDOUT, "have errno";
		is "$!", $_[1], "have error arg";
		undef $r;
		$cv->send;
	});
	return $r;
};


__END__

my $cv = AE::cv;
my $r;my $w;
tcp_connect 0, $port, sub {
	$r = AnyEvent::RW::RQ->new(
		fh => $_[0],
		timeout => 1,
	);
	weaken($w = $r);
	$r->push_write("timeout 0.1\n");
	$r->push_read(line => sub {
		is $_[0], "ready", "received ready" or diag $_[1];
		undef $r;
		$cv->send;
	});
};
$cv->recv;
ok !$w, '$r destroyed';



exit;
__END__



=for rem

tcp_connect 'localhost', '9999', sub {
	warn @_;
	defined &DB::enable_profile and DB::enable_profile();
	my $at = time;
	my $r;$r = AnyEvent::RW::RQ->new(
		fh => $_[0],
		#timeout => 1,
		on_end => sub {
			warn "on_end: @_";
		},
		on_timeout1 => sub {
			warn "on_timeout: @_";
		},
	);
	#use Devel::FindRef;
	#warn Devel::FindRef::track $r;
};

=cut

=for rem

tcp_connect 'localhost', '9999', sub {
	warn @_;
	defined &DB::enable_profile and DB::enable_profile();
	my $at = time;
	my $r;$r = AnyEvent::RW::RQ->new(
		fh => $_[0],
		timeout => 1,
		on_end => sub {
			warn "on_end: @_";
		},
		on_timeout1 => sub {
			warn "on_timeout: @_";
		},
		on_destroy => sub {
			warn "destroying";
		},
	);
	$r->push_read(line => sub {
		warn dumper \@_;
		undef $r;
	});
};

=cut

AE::cv->recv;