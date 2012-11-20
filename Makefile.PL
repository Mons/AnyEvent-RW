use 5.008008;
use ExtUtils::MakeMaker;

our $AUTHOR = -e '.gitignore';
if ($AUTHOR) {
	#system( 'pod2text lib/XML/Fast.pm > README' ) and die "$!";
}

WriteMakefile(
	NAME              => 'AnyEvent::RW',
	VERSION_FROM      => 'lib/AnyEvent/RW.pm',
	ABSTRACT_FROM     => 'lib/AnyEvent/RW.pm',
	PREREQ_PM         => { AnyEvent => 5 },
	AUTHOR            => 'Mons Anderson <mons@cpan.org>',
	META_ADD          => { license => 'perl' },
	
	PL_FILES          => {
		"Kit.pm.PL" => '$(INST_LIB)/AnyEvent/RW/Kit.pm',
		$AUTHOR ? (
			"Kit.pm.PL" => 'lib/AnyEvent/RW/Kit.pm',
		) : ()
	},
	clean             => { FILES => "Kit.pm" },
);

__END__
use inc::Module::Install;

my $MI  = $Module::Install::MAIN;
name           'AnyEvent-RW';
all_from       'lib/AnyEvent/RW.pm';
author         'Mons Anderson <mons@cpan.org>';
license        'perl';

build_requires 'Test::More';
build_requires 'lib::abs',  '0.90';

requires 'common::sense',    2;
requires 'AnyEvent',         5;
# requires 'uni::perl';

auto_provides;
auto_install;

WriteAll;

print STDERR "Generated makefile for ".$MI->load('name')->name."-".$MI->load('version')->version."\n";
