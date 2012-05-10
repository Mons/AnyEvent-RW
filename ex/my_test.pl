#!/usr/bin/env perl

use lib::abs '..';


use AnyEvent::RW::RQ;

use uni::perl ':dumper';

use AnyEvent::Impl::Perl;
use AE;
use AnyEvent::Socket;
use Time::HiRes 'time';
$| = 1;

my $recv;
sub M () { 1024*1024 }

tcp_connect 'google.com', '80', sub {
	warn @_;
	defined &DB::enable_profile and DB::enable_profile();
	my $at = time;
	my $r;$r = AnyEvent::RW::RQ->new(
		fh => $_[0],
		on_end => sub {
			warn "on_end: @_";
		},
	);
	$r->push_write("GET / HTTP/1.0\n\n");
	$r->push_read(line => sub {
		warn dumper \@_;
		$r->push_read(qr/\r?\n\r?\n/, sub {
			warn dumper \@_;
			$r->push_read(chunk => 4, sub {
				warn dumper \@_;
				$r->push_read(all => sub {
					warn dumper \@_;
					$r->push_read(all => sub {
						warn dumper \@_;
					});
				});
			});
		})
	});1
};


AE::cv->recv;