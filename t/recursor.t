use Test::More;

use 5.14.2;
use strict;
use warnings;
use List::Util qw[max];

use Zonemaster::Engine::Nameserver;
use Zonemaster::Engine::Util;
BEGIN { use_ok( 'Zonemaster::Engine::Recursor' ) }

my $datafile = 't/recursor.data';
if ( not $ENV{ZONEMASTER_RECORD} ) {
    die "Stored data file missing" if not -r $datafile;
    Zonemaster::Engine::Nameserver->restore( $datafile );
    Zonemaster::Engine::Profile->effective->set( q{no_network}, 1 );
}

my $p = Zonemaster::Engine::Recursor->recurse( 'www.iis.se' );
isa_ok( $p, 'Zonemaster::Engine::Packet' );
ok( $p->answer > 0, 'answer records' );
my ( $rr ) = $p->answer;
is( name( $rr->name ), 'www.iis.se', 'RR name ok' );

my $p2 = Zonemaster::Engine::Recursor->recurse( 'www.wiccainfo.se' );
isa_ok( $p2, 'Zonemaster::Engine::Packet' );
is( scalar( $p2->answer ), 1, 'answer records' );

is_parent( 'iis.se',                                                                   'se' );
is_parent( 'www.iis.se',                                                               'iis.se' );
is_parent( 'pp.se',                                                                    'se' );
is_parent( 'sno.pp.se',                                                                'se' );
is_parent( '2.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.4.9.5.0.7.2.0.0.0.7.4.0.1.0.0.2.ip6.arpa', '0.7.4.0.1.0.0.2.ip6.arpa' );
is_parent( '.',                                                                        '.' );
is_parent( 'foo.bar.baz.example.org',                                                  'example.org' );
is_parent( 'xx--doesnotexist.se',                                                      'se' );
is_parent( 'xx--doesnotexist.com',                                                     'com' );
is_parent( 'pewc.eu',                                                                  'eu' );
is_parent( 'melbourneit.com.au',                                                       'com.au' );

sub is_parent {
    my ( $name, $pname ) = @_;

    my $pn = Zonemaster::Engine::Recursor->parent( $name );
    is( $pn, $pname, "parent for $name is $pn" );
}

my ( $name, $packet ) = Zonemaster::Engine::Recursor->parent( 'www.iis.se' );
isa_ok( $packet, 'Zonemaster::Engine::Packet' );
is( $name, 'iis.se', 'name ok' );
ok( $packet->no_such_record, 'expected packet content' );

my @addr = Zonemaster::Engine::Recursor->get_addresses_for( 'ns.nic.se' );
isa_ok( $_, 'Net::IP::XS' ) for @addr;
is( $addr[0]->short, '212.247.7.228',      'expected address' );
is( $addr[1]->short, '2a00:801:f0:53::53', 'expected address' );

my $ns_count    = Zonemaster::Engine::Nameserver->all_known_nameservers;
my $cache_count = keys %Zonemaster::Engine::Nameserver::Cache::object_cache;
ok( $cache_count < $ns_count, 'Fewer cache than ns' );

if ( $ENV{ZONEMASTER_RECORD} ) {
    Zonemaster::Engine::Nameserver->save( $datafile );
}

done_testing;
