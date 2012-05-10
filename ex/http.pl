package AnyEvent::HTTP::Fast;

use lib::abs '..';
use uni::perl ':dumper';
#use EV;
use AnyEvent::Impl::Perl;
use URI;
use HTTP::Easy;
use HTTP::Parser::XS;
use AnyEvent::Socket;
#use AnyEvent::DNS
use AnyEvent::CacheDNS ':register';
use AnyEvent::RW::RQ;

sub http_request {
	my $cb = pop;
	my $method = uc shift;
	my ($url, %args) = @_;
	ref $url or $url = URI->new($url);
	my %s; $s{_} = \%s;
	my %hdr = (
		Host => $url->host,
		connection => 'close',
	);
	warn "connect " . $url->host;
	$s{con} = tcp_connect $url->host, $url->port // 80, sub {
		my $fh = shift;pop;
=for rem
		select+(select($fh), $|=1)[0];
		binmode $fh,':raw';
		
		$s{io} = AE::io $fh,0,sub {
			warn "io rw";
			my $i;
			while ( $i = sysread($fh,my $buf, 4096) ) {
				warn "$i / $!";
			}
			warn "$i / $!";
			$s{ww} = AE::io $fh,1,sub {
				warn "io ww";
				warn syswrite($fh,"GET / HTTP/1.0\n\n");
				delete $s{ww};
			};
		};
		syswrite($fh,"GET / HTTP/1.0\n\n");
		#shutdown $fh, 2;
		return;
=cut
		warn dumper \@_;
		my $buf;
		$s{h} = AnyEvent::RW->new(
			fh => $fh,
			debug => 0,
			read_size => 64*1024,
			read => sub {
				#warn "read @_";
				$buf .= ${$_[0]} if ref $_[0];
				unless ($s{hdr}) {
					my($ret, $minor_version, $status, $message, $headers) = 
						HTTP::Parser::XS::parse_http_response($buf, HTTP::Parser::XS::HEADERS_AS_ARRAYREF);
					if ($ret == -1) {
						warn "need more ".dumper $buf;
						return;
					}
					elsif($ret == -2) {
						warn "Broken ".dumper $buf;
						#return %s = ();
						return;
					}
					else {
						my %hdr = ( @$headers, Status => $status, Reason => $message );
						#warn "Success ".dumper \%hdr;
						$s{hdrl} = $ret;
						$s{hdr} = \%hdr;
						#delete $s{hdr}{'content-length'};
					}
				}
				my $ret = $s{hdrl};
				if (exists $s{hdr}{'content-length'}) {
					if (length $buf < $ret + $s{hdr}{'content-length'}) {
						warn "Buffer too small";
						return;
					} else {
						$cb->( substr($buf, $ret), $s{hdr} );
						%s = ();
					}
				}
				elsif ($s{h}->{_eof}) {
					$cb->( substr($buf, $ret), $s{hdr} );
					%s = ();
				}
				else {
					warn "We don't know content length and not closed";
					return;
				}
			},
		);
		$s{h}->push_write(
			"$method ".$url->path." HTTP/1.0\015\012"
			. (join "", map "\u$_: $hdr{$_}\015\012", grep defined $hdr{$_}, keys %hdr)
			. "\015\012"
			. (delete $args{body})
		);
	};
	return;
	# TODO: headers
}

http_request
	GET => 'http://google.com/',
	cb => sub {
		warn dumper \@_;
	};

#EV::loop;
AE::cv->recv;
