# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AgentAppointmentList;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);
use Kernel::Language qw(Translatable);

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $Output;

    # get param object
    my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');

    # get names of all parameters
    my @ParamNames = $ParamObject->GetParamNames();

    # get params
    my %GetParam;

    KEY:
    for my $Key (@ParamNames) {
        next KEY if $Key eq 'AppointmentIDs';
        $GetParam{$Key} = $ParamObject->GetParam( Param => $Key );
    }

    # get needed objects
    my $ConfigObject      = $Kernel::OM->Get('Kernel::Config');
    my $LayoutObject      = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $CalendarObject    = $Kernel::OM->Get('Kernel::System::Calendar');
    my $AppointmentObject = $Kernel::OM->Get('Kernel::System::Calendar::Appointment');
    my $PluginObject      = $Kernel::OM->Get('Kernel::System::Calendar::Plugin');

    my $JSON = $LayoutObject->JSONEncode( Data => [] );

    $LayoutObject->ChallengeTokenCheck();

    # check request
    if ( $Self->{Subaction} eq 'ListAppointments' ) {

        if ( $GetParam{CalendarID} ) {

            # append midnight to the timestamps
            for my $Timestamp (qw(StartTime EndTime)) {
                if ( $GetParam{$Timestamp} && !( $GetParam{$Timestamp} =~ /\s\d{2}:\d{2}:\d{2}$/ ) ) {
                    $GetParam{$Timestamp} = $GetParam{$Timestamp} . ' 00:00:00',
                }
            }

            # reset empty parameters
            for my $Param ( sort keys %GetParam ) {
                if ( !$GetParam{$Param} ) {
                    $GetParam{$Param} = undef;
                }
            }

            my @Appointments = $AppointmentObject->AppointmentList(
                %GetParam,
            );

            # get user timezone offset
            $Self->{UserTimeZone} = $Kernel::OM->Get('Kernel::System::Calendar::Helper')->TimezoneOffsetGet(
                UserID => $Self->{UserID},
            );

            # go through all appointments
            for my $Appointment (@Appointments) {

                # calculate local times
                $Appointment->{TimezoneID} = $Appointment->{TimezoneID} ? $Appointment->{TimezoneID} : 0;

                my $StartTime = $Kernel::OM->Get('Kernel::System::Calendar::Helper')->SystemTimeGet(
                    String => $Appointment->{StartTime},
                );
                $StartTime -= $Appointment->{TimezoneID} * 3600;
                $StartTime += $Self->{UserTimeZone} * 3600;
                $Appointment->{StartTime} = $Kernel::OM->Get('Kernel::System::Calendar::Helper')->TimestampGet(
                    SystemTime => $StartTime,
                );

                my $EndTime = $Kernel::OM->Get('Kernel::System::Calendar::Helper')->SystemTimeGet(
                    String => $Appointment->{EndTime},
                );
                $EndTime -= $Appointment->{TimezoneID} * 3600;
                $EndTime += $Self->{UserTimeZone} * 3600;
                $Appointment->{EndTime} = $Kernel::OM->Get('Kernel::System::Calendar::Helper')->TimestampGet(
                    SystemTime => $EndTime,
                );

                if ( $Appointment->{RecurrenceUntil} ) {
                    my $RecurrenceUntil = $Kernel::OM->Get('Kernel::System::Calendar::Helper')->SystemTimeGet(
                        String => $Appointment->{RecurrenceUntil},
                    );
                    $RecurrenceUntil -= $Appointment->{TimezoneID} * 3600;
                    $RecurrenceUntil += $Self->{UserTimeZone} * 3600;
                    $Appointment->{RecurrenceUntil}
                        = $Kernel::OM->Get('Kernel::System::Calendar::Helper')->TimestampGet(
                        SystemTime => $RecurrenceUntil,
                        );
                }

                # include resource data
                $Appointment->{TeamName}      = '';
                $Appointment->{ResourceNames} = '';

                if (
                    $Kernel::OM->Get('Kernel::System::Main')->Require(
                        'Kernel::System::Calendar::Team',
                        Silent => 1,
                    )
                    )
                {
                    if ( $Appointment->{TeamID} ) {
                        my %Team = $Kernel::OM->Get('Kernel::System::Calendar::Team')->TeamGet(
                            TeamID => $Appointment->{TeamID},
                            UserID => $Self->{UserID},
                        );
                        $Appointment->{TeamName} = $Team{Name} if %Team;
                    }
                    if ( $Appointment->{ResourceID} ) {
                        my $UserObject = $Kernel::OM->Get('Kernel::System::User');
                        my @ResourceNames;
                        RESOURCE:
                        for my $ResourceID ( @{ $Appointment->{ResourceID} } ) {
                            next RESOURCE if !$ResourceID;
                            my %User = $UserObject->GetUserData(
                                UserID => $ResourceID,
                            );
                            push @ResourceNames, $User{UserFullname};
                        }

                        # truncate more than three elements
                        if ( scalar @ResourceNames > 3 ) {
                            splice @ResourceNames, 3;
                            $ResourceNames[2] .= '...';
                        }

                        $Appointment->{ResourceNames} = join( '\n', @ResourceNames );
                    }
                }
            }

            # build JSON output
            $JSON = $LayoutObject->JSONEncode(
                Data => (
                    \@Appointments,
                ),
            );
        }
    }

    elsif ( $Self->{Subaction} eq 'NonBusinessHours' ) {

        # get working hours from sysconfig
        my $TimeWorkingHours = $ConfigObject->Get('TimeWorkingHours');

        # create non-business hour appointments for each day
        my @NonBusinessHours;
        for my $DayName ( sort keys %{$TimeWorkingHours} ) {

            # day of the week
            my $DoW = 0;    # Sun
            if ( $DayName eq 'Mon' ) {
                $DoW = 1;
            }
            elsif ( $DayName eq 'Tue' ) {
                $DoW = 2;
            }
            elsif ( $DayName eq 'Wed' ) {
                $DoW = 3;
            }
            elsif ( $DayName eq 'Thu' ) {
                $DoW = 4;
            }
            elsif ( $DayName eq 'Fri' ) {
                $DoW = 5;
            }
            elsif ( $DayName eq 'Sat' ) {
                $DoW = 6;
            }

            my $StartTime = 0;
            my $EndTime   = 0;

            ENDTIME:
            for ( $EndTime = 0; $EndTime < 24; $EndTime++ ) {

                # is this working hour?
                if ( grep { $_ eq $EndTime } @{ $TimeWorkingHours->{$DayName} } ) {

                    # add appointment
                    if ( $EndTime > $StartTime ) {
                        push @NonBusinessHours, {
                            StartTime => sprintf( '%02d:00:00', $StartTime ),
                            EndTime   => sprintf( '%02d:00:00', $EndTime ),
                            DoW       => [$DoW],
                        };
                    }

                    # go to the end of the working hours
                    for ( my $EndHour = $EndTime; $EndHour < 24; $EndHour++ ) {
                        if ( !grep { $_ eq $EndHour } @{ $TimeWorkingHours->{$DayName} } ) {
                            $EndTime = $StartTime = $EndHour;
                            next ENDTIME;
                        }
                    }
                }
            }

            # last appointment
            if ( $StartTime < $EndTime ) {
                push @NonBusinessHours, {
                    StartTime => sprintf( '%02d:00:00', $StartTime ),
                    EndTime   => sprintf( '%02d:00:00', $EndTime ),
                    DoW       => [$DoW],
                };
            }
        }

        # collapse appointments with same start and end times
        for my $AppointmentA (@NonBusinessHours) {
            for my $AppointmentB (@NonBusinessHours) {
                if (
                    $AppointmentA->{StartTime} && $AppointmentB->{StartTime}
                    && $AppointmentA->{StartTime} eq $AppointmentB->{StartTime}
                    && $AppointmentA->{EndTime} eq $AppointmentB->{EndTime}
                    && $AppointmentA->{DoW} ne $AppointmentB->{DoW}
                    )
                {
                    push @{ $AppointmentA->{DoW} }, @{ $AppointmentB->{DoW} };
                    $AppointmentB = undef;
                }
            }
        }
        @NonBusinessHours = grep { scalar keys %{$_} } @NonBusinessHours;

        # build JSON output
        $JSON = $LayoutObject->JSONEncode(
            Data => (
                \@NonBusinessHours,
            ),
        );
    }

    elsif ( $Self->{Subaction} eq 'AppointmentDays' ) {

        # append midnight to the timestamps
        for my $Timestamp (qw(StartTime EndTime)) {
            if ( $GetParam{$Timestamp} && !( $GetParam{$Timestamp} =~ /\s\d{2}:\d{2}:\d{2}$/ ) ) {
                $GetParam{$Timestamp} = $GetParam{$Timestamp} . ' 00:00:00',
            }
        }

        # reset empty parameters
        for my $Param ( sort keys %GetParam ) {
            if ( !$GetParam{$Param} ) {
                $GetParam{$Param} = undef;
            }
        }

        my %AppointmentDays = $AppointmentObject->AppointmentDays(
            %GetParam,
            UserID => $Self->{UserID},
        );

        # build JSON output
        $JSON = $LayoutObject->JSONEncode(
            Data => (
                \%AppointmentDays,
            ),
        );
    }
    elsif ( $Self->{Subaction} eq 'AppointmentsStarted' ) {
        my $Show = 0;

        my @AppointmentIDs = $ParamObject->GetArray( Param => 'AppointmentIDs[]' );

        # check if team object is registered
        my $ShowResources
            = $Kernel::OM->Get('Kernel::System::Main')->Require( 'Kernel::System::Calendar::Team', Silent => 1 );

        for my $AppointmentID (@AppointmentIDs) {
            my $Seen = $AppointmentObject->AppointmentSeenGet(
                AppointmentID => $AppointmentID,
                UserID        => $Self->{UserID},
            );

            if ( !$Seen ) {
                my %Appointment = $AppointmentObject->AppointmentGet(
                    AppointmentID => $AppointmentID,
                );

                my @Resources = ();
                if ($ShowResources) {
                    for my $UserID ( @{ $Appointment{ResourceID} } ) {
                        if ($UserID) {
                            my %User = $Kernel::OM->Get('Kernel::System::User')->GetUserData(
                                UserID => $UserID,
                            );
                            push @Resources, $User{UserFullname};
                        }
                    }
                }

                $LayoutObject->Block(
                    Name => 'Appointment',
                    Data => {
                        %Appointment,
                        ShowResources => $ShowResources,
                        Resource      => join( ', ', @Resources ),
                    },
                );

                # system displays reminder this time, mark it as shown
                $AppointmentObject->AppointmentSeenSet(
                    AppointmentID => $AppointmentID,
                    UserID        => $Self->{UserID},
                );

                $Show = 1;
            }
        }

        my $HTML = $LayoutObject->Output(
            TemplateFile => 'AgentAppointmentCalendarOverviewSeen',
            Data         => {
                ShowResources => $ShowResources,
            },
        );

        $JSON = $LayoutObject->JSONEncode(
            Data => {
                HTML  => $HTML,
                Show  => $Show,
                Title => $LayoutObject->{LanguageObject}->Translate("Ongoing appointments"),
            },
        );
    }

    # send JSON response
    return $LayoutObject->Attachment(
        ContentType => 'application/json; charset=' . $LayoutObject->{Charset},
        Content     => $JSON,
        Type        => 'inline',
        NoCache     => 1,
    );

    return;
}

1;
