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

tcp_connect 'localhost', '9999', sub {
	warn @_;
	defined &DB::enable_profile and DB::enable_profile();
	my $at = time;
	my $h;$h = AnyEvent::Handle->new(
		fh => $_[0],
#		read_size => 4096, max_read_size => 4096,
		on_read => sub {
			$recv += length $h->{rbuf};
			#substr($h->{rbuf},0) = '';
			$h->{rbuf} = '';
			#warn dumper $h;
			if ( $recv > 1000 * M ) {
				warn "read_size = $h->{read_size}\n";
				printf "\r              \r%0.1fM, %0.3fM/s   ", $recv/M, $recv / M / (time - $at);
				exit;
			};
		},
		on_eof => sub {
			warn "end: @_";
		},
	);
	#$r->push_write("GET / HTTP/1.0\n\n");
	#$r->push_write("GET / HTTP/1.0\n\n");
	#warn dumper $r;
};


AE::cv->recv;