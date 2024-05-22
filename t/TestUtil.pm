package TestUtil;

use 5.014002;

use strict;
use warnings;

use Test::More;
use Zonemaster::Engine;
use Exporter 'import';

use Carp qw( croak );

BEGIN {
    our @EXPORT_OK = qw[ perform_testcase_testing perform_methodsv2_testing ];
    our %EXPORT_TAGS = ( all => \@EXPORT_OK );

    ## no critic (Modules::ProhibitAutomaticExportation)
    our @EXPORT = qw[ perform_testcase_testing perform_methodsv2_testing ];
}

=head1 NAME

TestUtil - a set of methods to ease Zonemaster::Engine unit testing

=head1 SYNOPSIS

Because this package lies in the testing folder C<t/> and that folder is
unknown to the include path @INC, it can be including using the following code:

    use File::Basename qw( dirname );
    use File::Spec::Functions qw( rel2abs );
    use lib dirname( rel2abs( $0 ) );
    use TestUtil;

=head1 METHODS

=over

=item perform_methodsv2_testing()

    perform_methodsv2_testing( );

TODO

=item perform_testcase_testing()

    perform_testcase_testing( $test_case, $test_module, $aref_alltags, %subtests );

This method loads unit test data (test case name, test module name, array of all message tags and test scenarios) and,
after some data checks and if the test scenario is testable, it runs the specified test case and checks for the presence
(or absence) of specific message tags for each specified test scenario.

Takes a string (test case name), a string (test module name) and a hash - the keys of which are scenario names
(in all uppercase), and their corresponding values are an array of:

=over

=item *
a boolean (testable), 1 or 0

=item *
a string (zone name)

=item *
an array of strings (mandatory message tags), which could be empty, or undef

=item *
an array of strings (forbidden message tags), which could be empty, or undef

=item *
an array of name server expressions for undelegated name servers

=item *
an array of DS expressions for "undelegated" DS

=back

The array of mandatory message tags or the array of forbidden message tags, but not both, could be
undefined. If the mandatory message tag array is undefined, then it will be generated to contain
all message tags not included in the forbidden message tag array. The same mechanism is used if the
forbidden message tag array is undefined.

The arrays of mandatory message tags and forbidden message tags, respectively, can be empty, but not
both. At least one of the arrays must be non-empty.

The name server expression has the format "name-server-name/IP" or only "name-server-name". The DS expression
has the format "keytag,algorithm,type,digest". Those two expressions have the same format as the data for
--ns and --ds options, respectively, for I<zonemaster-cli>.

=back

=cut

sub perform_methodsv2_testing {
    my ( %subtests ) = @_;

    for my $scenario ( sort ( keys %subtests ) ) {
        my ( $testable,
             $zone_name,
             $expected_ns_ip,
             $undelegated_ns,
             $undelegated_ds
            ) = @{ $subtests{$scenario} };

        subtest $scenario => sub {
            my @all_methods_names = qw( get_parent_ns_ips
                _get_oob_ips
                _get_delegation
                get_del_ns_names_and_ips
                get_del_ns_names
                get_del_ns_ips
                get_zone_ns_names
                _get_ib_addr_in_zone
                get_zone_ns_names_and_ips
                get_zone_ns_ips
            );

            if ( @$undelegated_ns ) {
                my %undel_ns;
                foreach my $nsexp ( @$undelegated_ns ) {
                    my ( $ns, $ip ) = split m(/), $nsexp;
                    croak "Scenario $scenario: Name server name '$ns' in '$nsexp' is not valid" if $ns !~ /^[0-9A-Za-z-.]+$/;
                    if ( $ip ) {
                        croak "Scenario $scenario: IP address '$ip' in '$nsexp' is not valid" if
                            $ip !~ /^([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\.([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])){3}$/ and
                            $ip !~ /^((?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}|(?:[0-9A-Fa-f]{1,4}:){1,7}:|:(?::[0-9A-Fa-f]{1,4}){1,7}|
                                   [0-9A-Fa-f]{1,4}:(?:(?::[0-9A-Fa-f]{1,4}){1,6})|:(?:(?::[0-9A-Fa-f]{1,4}){1,7}|:)|
                                   (?:(?:[0-9A-Fa-f]{1,4}:){1,6}:[0-9A-Fa-f]{1,4})|(?:(?:[0-9A-Fa-f]{1,4}:){1,5}:(?:[0-9A-Fa-f]{1,4}:){1,2})|
                                   (?:(?:[0-9A-Fa-f]{1,4}:){1,4}:(?:[0-9A-Fa-f]{1,4}:){1,3})|(?:(?:[0-9A-Fa-f]{1,4}:){1,3}:(?:[0-9A-Fa-f]{1,4}:){1,4})|
                                   (?:(?:[0-9A-Fa-f]{1,4}:){1,2}:(?:[0-9A-Fa-f]{1,4}:){1,5}))$/x; # IPv4 and IPv6, respectively
                    }
                    $undel_ns{$ns} //= [];
                    push @{ $undel_ns{$ns} }, $ip if $ip;
                }

                Zonemaster::Engine->add_fake_delegation( $zone_name => \%undel_ns, fill_in_empty_oob_glue => 0 );
            }

            # for my $method ( @all_methods_names ) {
            #     my $res = Zonemaster::Engine::TestMethodsV2->$method( Zonemaster::Engine->zone( $zone_name ) );
            # }

            my $res = Zonemaster::Engine::TestMethodsV2->get_zone_ns_ips( Zonemaster::Engine->zone( $zone_name ) );

            foreach my $expected_ip ( @{$expected_ns_ip} ) {
                ok( grep( /^$expected_ip$/, @{$res} ), "IP $expected_ip is present" )
                    or diag "IP '$expected_ip' should have been present, but wasn't";
            }

            ok( scalar @{$res} == scalar @{$expected_ns_ip} ) or diag "Number of IP addresses in both arrays does not match";
        }
    }
}


sub perform_testcase_testing {
    my ( $test_case, $test_module, $aref_alltags, %subtests ) = @_;

    my @untested_scenarios = ();

    if ( ref( $aref_alltags ) ne 'ARRAY' ) {
        croak 'All tags array variable must be an array ref'
    }

    foreach my $t (@$aref_alltags) {
        croak "Invalid tag in 'all tags': '$t'" unless $t =~ /^[A-Z]+[A-Z0-9_]*[A-Z0-9]$/;
    }

    for my $scenario ( sort ( keys %subtests ) ) {
        if ( ref( $scenario ) ne '' or $scenario ne uc($scenario) ) {
            croak "Scenario $scenario: Key must (i) not be a reference and (ii) be in all uppercase";
        }

        if ( scalar @{ $subtests{$scenario} } != 6 ) {
            croak "Scenario $scenario: Incorrect number of values. " .
                "Correct format is: { SCENARIO_NAME => [" .
                "testable " .
                "zone_name, " .
                "[ MANDATORY_MESSAGE_TAGS ], " .
                "[ FORBIDDEN_MESSAGE_TAGS ], " .
                "[ UNDELEGATED_NS ], " .
                "[ UNDELEGATED_DS ], " .
                " ] }";
        }

        my ( $testable,
             $zone_name,
             $mandatory_message_tags,
             $forbidden_message_tags,
             $undelegated_ns,
             $undelegated_ds
            ) = @{ $subtests{$scenario} };

        if ( ref( $testable ) ne '' ) {
            croak "Scenario $scenario: Type of testable must not be a reference";
        }

        if ( $testable != 1 and $testable != 0 ) {
            croak "Scenario $scenario: Value of testable must be 0 or 1";
        }

        if ( ref( $zone_name ) ne '' ) {
            croak "Scenario $scenario: Type of zone name must not be a reference";
        }

        if ( $zone_name !~ m(^[A-Za-z0-9/_.-]+$) ) {
            croak "Scenario $scenario: Zone name '$zone_name' is not valid";
        }

        if ( ! defined( $mandatory_message_tags ) and !defined( $forbidden_message_tags ) ) {
            croak "Scenario $scenario: Not both array of mandatory tags and array of forbidden tags can be undefined";
        }

        if ( defined( $mandatory_message_tags ) and defined( $forbidden_message_tags ) and
             not scalar @{ $mandatory_message_tags } and not scalar @{ $forbidden_message_tags } ) {
            croak "Scenario $scenario: Not both arrays of mandatory message tags and forbidden message tags, respectively, can be empty";
        }

        if ( defined( $mandatory_message_tags ) and ref( $mandatory_message_tags ) ne 'ARRAY' ) {
            croak "Scenario $scenario: Incorrect reference type of mandatory message tags. Expected: ARRAY";
        }

        if ( defined( $forbidden_message_tags ) and ref( $forbidden_message_tags ) ne 'ARRAY' ) {
            croak "Scenario $scenario: Incorrect reference type of forbidden message tags. Expected: ARRAY";
        }

        if ( ! defined( $mandatory_message_tags ) ) {
            my @tags;
            foreach my $t ( @$aref_alltags ) {
                push @tags, $t unless grep( /^$t$/, @$forbidden_message_tags );
            }
            $mandatory_message_tags = \@tags;
        }

        if ( ! defined( $forbidden_message_tags ) ) {
            my @tags;
            foreach my $t ( @$aref_alltags ) {
                push @tags, $t unless grep( /^$t$/, @$mandatory_message_tags );
            }
            $forbidden_message_tags = \@tags;
        }

        foreach my $tag ( @$mandatory_message_tags ) {
            croak "Scenario $scenario: Invalid message tag in 'mandatory_message_tags': '$tag'" unless $tag =~ /^[A-Z]+[A-Z0-9_]*[A-Z0-9]$/;
        }

        foreach my $tag ( @$mandatory_message_tags ) {
            unless ( grep( /^$tag$/, @$aref_alltags ) ) {
                croak "Scenario $scenario: Message tag '$tag' in 'mandatory_message_tags' is missing in 'all_tags'";
            }
        }

        foreach my $tag ( @$forbidden_message_tags ) {
            croak "Scenario $scenario: Invalid message tag in 'forbidden_message_tags': '$tag'" unless $tag =~ /^[A-Z]+[A-Z0-9_]*[A-Z0-9]$/;
        }

        foreach my $tag ( @$forbidden_message_tags ) {
            unless ( grep( /^$tag$/, @$aref_alltags ) ) {
                croak "Scenario $scenario: Message tag '$tag' in 'forbidden_message_tags' is missing in 'all_tags'";
            }
        }

        if ( ref( $undelegated_ns ) ne 'ARRAY' ) {
            croak "Scenario $scenario: Incorrect reference type of undelegated name servers expressions. Expected: ARRAY";
        }

        if ( ref( $undelegated_ds ) ne 'ARRAY' ) {
            croak "Scenario $scenario: Incorrect reference type of undelegated DS expressions. Expected: ARRAY";
        }

        if ( not $testable ) {
            push @untested_scenarios, $scenario;
            next;
        }

        subtest $scenario => sub {

            if ( @$undelegated_ns ) {
                my %undel_ns;
                foreach my $nsexp ( @$undelegated_ns ) {
                    my ($ns, $ip) = split m(/), $nsexp;
                    croak "Scenario $scenario: Name server name '$ns' in '$nsexp' is not valid" if $ns !~ /^[0-9A-Za-z-.]+$/;
                    if ($ip) {
                        croak "Scenario $scenario: IP address '$ip' in '$nsexp' is not valid" if
                            $ip !~ /^([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\.([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])){3}$/ and
                            $ip !~ /^((?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}|(?:[0-9A-Fa-f]{1,4}:){1,7}:|:(?::[0-9A-Fa-f]{1,4}){1,7}|
                                   [0-9A-Fa-f]{1,4}:(?:(?::[0-9A-Fa-f]{1,4}){1,6})|:(?:(?::[0-9A-Fa-f]{1,4}){1,7}|:)|
                                   (?:(?:[0-9A-Fa-f]{1,4}:){1,6}:[0-9A-Fa-f]{1,4})|(?:(?:[0-9A-Fa-f]{1,4}:){1,5}:(?:[0-9A-Fa-f]{1,4}:){1,2})|
                                   (?:(?:[0-9A-Fa-f]{1,4}:){1,4}:(?:[0-9A-Fa-f]{1,4}:){1,3})|(?:(?:[0-9A-Fa-f]{1,4}:){1,3}:(?:[0-9A-Fa-f]{1,4}:){1,4})|
                                   (?:(?:[0-9A-Fa-f]{1,4}:){1,2}:(?:[0-9A-Fa-f]{1,4}:){1,5}))$/x; # IPv4 and IPv6, respectively
                    }
                    $undel_ns{$ns} //= [];
                    push @{ $undel_ns{$ns} }, $ip if $ip;
                }

                Zonemaster::Engine->add_fake_delegation( $zone_name => \%undel_ns, fill_in_empty_oob_glue => 0 );
            }

            if ( @$undelegated_ds ) {
                my @data;
                foreach my $str ( @$undelegated_ds ) {
                    my ( $tag, $algo, $type, $digest ) = split( /,/, $str );
                    croak "Scenario $scenario: DS expression '$str' is not valid" if
                        $tag !~ /^[0-9]+$/ or $algo !~ /^[0-9]+$/ or $type !~ /^[0-9]+$/ or $digest !~ /^[0-9a-fA-F]{4,}/;
                    push @data, { keytag => $tag, algorithm => $algo, type => $type, digest => $digest };
                }
                Zonemaster::Engine->add_fake_ds( $zone_name => \@data );
            }

            my @messages = Zonemaster::Engine->test_method( $test_module, $test_case, Zonemaster::Engine->zone( $zone_name ) );
            my %res = map { $_->tag => 1 } @messages;

            if ( my ( $error ) = grep { $_->tag eq 'MODULE_ERROR' } @messages ) {
                diag("Module died with error: " . $error->args->{"msg"});
                fail("Test case executes properly");
            }
            else {
                for my $tag ( @{ $mandatory_message_tags } ) {
                    ok( exists $res{$tag}, "Tag $tag is outputted" )
                        or diag "Tag '$tag' should have been outputted, but wasn't";
                }
                for my $tag ( @{ $forbidden_message_tags } ) {
                    ok( !exists $res{$tag}, "Tag $tag is not outputted" )
                        or diag "Tag '$tag' was not supposed to be outputted, but it was";
                }
            }
        };
    }

    if ( @untested_scenarios ) {
        warn "Untested scenarios:\n";
        warn "\tScenario $_ cannot be tested.\n" for @untested_scenarios;
    }
}

1;
