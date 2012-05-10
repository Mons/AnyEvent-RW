#!/usr/bin/env perl


use uni::perl ':dumper';

use AnyEvent::Impl::Perl;
use AE;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Time::HiRes 'time';
$| = 1;

my $recv;
sub M () { 1024*1024 }
my $N = 5;
my $bs = 64*1024;
my $wbuf = "x"x$bs;

tcp_connect 'localhost', '9999', sub {
	warn @_;
	defined &DB::enable_profile and DB::enable_profile();
	my $at = time;
	my $sent = 0;
	my $r;$r = AnyEvent::Handle->new(
		fh => $_[0],
	);
	
	my $w;$w = AE::idle sub {
		$w;
		#if (length $r->{wbuf} > 100*$bs) {
		#	warn "wsize too big ($r->{wsize})";
		#	return;
		#}
		#warn "idle $r->{wsize}";
		for (1..$N) {
			$r->push_write($wbuf);
			$sent += length $wbuf;
		}
		printf "\r              \r%0.1fM, %0.3fM/s   ", $sent/M, $sent / M / (time - $at);
	};
	return;

	my $t;$t = AE::timer 0,.001, sub {
		$t;
		for (1..2) {
			$r->push_write($wbuf);
			$sent += length $wbuf;
		}
		printf "\r              \r%0.1fM, %0.3fM/s   ", $sent/M, $sent / M / (time - $at);
	};
	return;
};


AE::cv->recv;