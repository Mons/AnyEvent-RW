#!/usr/bin/env perl -w

use common::sense;
use lib::abs '../lib';
use Test::More tests => 2;
use Test::NoWarnings;

BEGIN {
	use_ok( 'AnyEvent::RW' );
}

diag( "Testing AnyEvent::RW $AnyEvent::RW::VERSION, Perl $], $^X" );
