#!/usr/bin/env perl


use lib::abs '..';
use AnyEvent::RW;
use uni::perl ':dumper';

use AnyEvent::Impl::Perl;
use AE;
use AnyEvent::Socket;
use Time::HiRes 'time';
$| = 1;

my $recv;
sub M () { 1024*1024 }

tcp_connect 'localhost', '9999', sub {
	warn @_;
	defined &DB::enable_profile and DB::enable_profile();
	my $at = time;
	my $r;$r = AnyEvent::RW->new(
		fh => $_[0],
#		read_size => 4096, max_read_size => 4096,
		read => sub {
			my $rbuf = shift;
			$recv += length $$rbuf;
#			printf "\r              \r%0.1fM, %0.3fM/s   ", $recv/M, $recv / M / (time - $at);
#			exit if $recv > 1000 * M;
			if ( $recv > 1000 * M ) {
				warn "Read size = $r->{read_size}";
				printf "\r              \r%0.1fM, %0.3fM/s   ", $recv/M, $recv / M / (time - $at);
				exit;
			};
			#warn dumper \@_;
		},
		end => sub {
			warn "end: @_";
		}
	);
	#$r->push_write("GET / HTTP/1.0\n\n");
	#$r->push_write("GET / HTTP/1.0\n\n");
	#warn dumper $r;
};


AE::cv->recv;