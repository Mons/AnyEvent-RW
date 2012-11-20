#!/usr/bin/env perl -w

use common::sense;
use lib::abs '../lib';
use Test::More tests => 5;
use Test::NoWarnings;

BEGIN {
	use_ok( 'AnyEvent::RW' );
	use_ok( 'AnyEvent::RW::RQ' );
	use_ok( 'AnyEvent::RW::TLS' );
	use_ok( 'AnyEvent::RW::TLSRQ' );
}

diag( "Testing AnyEvent::RW $AnyEvent::RW::VERSION, AnyEvent $AnyEvent::VERSION, Perl $], $^X" );
