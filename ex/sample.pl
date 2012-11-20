#!/usr/bin/env perl

use lib::abs '../lib';
use EV;
use uni::perl ':dumper';
use AnyEvent::RW;
use AnyEvent::RW::TLSRQ;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Net::SSLeay;

#my $t;$t = AE::timer 1,1,sub {$t; warn "XXXXXX";};

tcp_connect 'google.com', '443',sub {
	#my $h = AnyEvent::Handle->new( fh => shift() );
	my $h = AnyEvent::RW->new( fh => shift() );
	my %s = (h=>$h);$s{_} = \%s;
	
	$h->starttls('connect');
	$h->upgrade("TLSRQ");
=for var 1
	$h->upgrade("TLSRQ", 'connect');
=cut
	$h->push_write("GET / HTTP/1.0\n\n");
	$h->push_read(line => sub {
		shift;
		warn "on_read: ".dumper \@_;
	});
	return;
	$h->{on_read} = sub {
		warn "read ".dumper \@_;
	};
	return;
	$h->push_read( line => sub {
		shift;
		warn dumper \@_;
		undef $h;
	} );
};

EV::loop;