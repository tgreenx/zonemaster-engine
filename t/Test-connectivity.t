use Test::More;
use File::Slurp;

use List::MoreUtils qw[uniq none any];

BEGIN {
    use_ok( q{Zonemaster::Engine} );
    use_ok( q{Zonemaster::Engine::Nameserver} );
    use_ok( q{Zonemaster::Engine::Test::Connectivity} );
    use_ok( q{Zonemaster::Engine::Util} );
}

my $datafile = q{t/Test-connectivity.data};
if ( not $ENV{ZONEMASTER_RECORD} ) {
    die q{Stored data file missing} if not -r $datafile;
    Zonemaster::Engine::Nameserver->restore( $datafile );
    Zonemaster::Engine::Profile->effective->set( q{no_network}, 1 );
}

my ($json, $profile_test);
foreach my $testcase ( qw{connectivity01 connectivity02 connectivity03} ) {
    $json          = read_file( 't/profiles/Test-'.$testcase.'-only.json' );
    $profile_test  = Zonemaster::Engine::Profile->from_json( $json );
    Zonemaster::Engine::Profile->effective->merge( $profile_test );
    my @testcases;
    foreach my $result ( Zonemaster::Engine->test_module( q{connectivity}, q{afnic.fr} ) ) {
        foreach my $trace (@{$result->trace}) {
            push @testcases, grep /Zonemaster::Engine::Test::Connectivity::connectivity/, @$trace;
        }
    }
    @testcases = uniq sort @testcases;
    is( scalar( @testcases ), 1, 'only one test-case ('.$testcase.')' );
    is( $testcases[0], 'Zonemaster::Engine::Test::Connectivity::'.$testcase, 'expected test-case ('.$testcases[0].')' );
}

$json         = read_file( 't/profiles/Test-connectivity-all.json' );
$profile_test = Zonemaster::Engine::Profile->from_json( $json );
Zonemaster::Engine::Profile->effective->merge( $profile_test );

my @res;
my %res;
my %should_emit;

my $metadata = Zonemaster::Engine::Test::Connectivity->metadata();
my $test_levels = Zonemaster::Engine::Profile->effective->{profile}->{test_levels}->{CONNECTIVITY};

sub check_output_connectivity_testcase {
    my ( $testcase, $res, $should_emit ) = @_;

    return if ( $testcase !~ q/connectivity0[1-3]/ );

    for my $key ( @{ $metadata->{$testcase} } ) {
        next if ( $test_levels->{$key} =~ q/DEBUG/ );
        if ( $should_emit->{$key} ) {
            ok( $res->{$key}, "Should emit $key" );
        } else {
            ok( !$res->{$key}, "Should NOT emit $key" );
        }
    }
}

sub check_output_connectivity_all {
    my ( $res, $should_emit ) = @_;

    check_output_connectivity_testcase( 'connectivity01', $res, $should_emit );
    check_output_connectivity_testcase( 'connectivity02', $res, $should_emit );
    check_output_connectivity_testcase( 'connectivity03', $res, $should_emit );
}

subtest 'All good' => sub {
    %res = map { $_->tag => 1 } Zonemaster::Engine->test_module( q{connectivity}, q{afnic.fr} );
    ok( !$res{MODULE_ERROR}, q{Test module completes normally} );
    %should_emit = (
        IPV4_DIFFERENT_ASN => 1,
        IPV6_DIFFERENT_ASN => 1
    );
    check_output_connectivity_all( \%res, \%should_emit );
};

subtest 'Nameservers with Uniq AS (IPv4 and IPv6)' => sub {
    %should_emit = (
        IPV4_ONE_ASN => 1,
        IPV6_ONE_ASN => 1,
    );
    %res = map { $_->tag => 1 } Zonemaster::Engine->test_module( q{connectivity}, q{001.tf} );
    check_output_connectivity_testcase( 'connectivity03', \%res, \%should_emit );
};

subtest 'Nameservers with Uniq AS (IPv4 only)' => sub {
    %should_emit = (
        IPV4_ONE_ASN => 1
    );
    %res = map { $_->tag => 1 } Zonemaster::Engine->test_module( q{connectivity}, q{zut-root.rd.nic.fr} );
    check_output_connectivity_testcase( 'connectivity03', \%res, \%should_emit );
};

subtest 'No IPv6 (profile with IPv4 only)' => sub {
    Zonemaster::Engine::Profile->effective->set( q{net.ipv4}, 1 );
    Zonemaster::Engine::Profile->effective->set( q{net.ipv6}, 0 );

    %res = map { $_->tag => 1 } Zonemaster::Engine->test_module( q{connectivity}, q{afnic.fr} );

    subtest 'UDP' => sub {
        %should_emit = (
            CN01_IPV6_DISABLED => 1
        );
        check_output_connectivity_testcase( 'connectivity01', \%res, \%should_emit );
    };

    subtest 'TCP (no messages)' => sub {
        %should_emit = ();
        check_output_connectivity_testcase( 'connectivity02', \%res, \%should_emit );
    };

    Zonemaster::Engine::Profile->effective->set( q{net.ipv6}, 1 );
};

subtest 'No IPv4 (profile with IPv6 only)' => sub {
    Zonemaster::Engine::Profile->effective->set( q{net.ipv4}, 0 );
    Zonemaster::Engine::Profile->effective->set( q{net.ipv6}, 1 );

    %res = map { $_->tag => 1 } Zonemaster::Engine->test_module( q{connectivity}, q{afnic.fr} );

    subtest 'UDP' => sub {
        %should_emit = (
            CN01_IPV4_DISABLED => 1
        );
        check_output_connectivity_testcase( 'connectivity01', \%res, \%should_emit );
    };

    subtest 'TCP (no messages)' => sub {
        %should_emit = ();
        check_output_connectivity_testcase( 'connectivity02', \%res, \%should_emit );
    };

    Zonemaster::Engine::Profile->effective->set( q{net.ipv4}, 1 );
};

subtest 'No network' => sub {
    Zonemaster::Engine::Profile->effective->set( q{net.ipv4}, 0 );
    Zonemaster::Engine::Profile->effective->set( q{net.ipv6}, 0 );

    %res = map{ $_->tag => 1 } Zonemaster::Engine->test_module( q{connectivity}, q{afnic.fr} );
    ok( $res{NO_NETWORK}, 'IPv6 and IPv4 disabled' );

    Zonemaster::Engine::Profile->effective->set( q{net.ipv4}, 1 );
    Zonemaster::Engine::Profile->effective->set( q{net.ipv6}, 1 );
};

if ( $ENV{ZONEMASTER_RECORD} ) {
    Zonemaster::Engine::Nameserver->save( $datafile );
}

done_testing;
