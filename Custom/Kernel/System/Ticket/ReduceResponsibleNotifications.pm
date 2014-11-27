# --
# Kernel/System/Ticket/ReduceResponsibleNotifications.pm - reduce amount of notifications mails for responsible persons
# Copyright (C) 2013 - 2014 Perl-Services.de, http://perl-services.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Ticket::ReduceResponsibleNotifications;

use strict;
use warnings;

use List::Util qw(first);

use Kernel::System::Ticket::Article;

no warnings 'redefine';

=head1 NAME

Kernel::System::Ticket::ReduceResponsibleNotifications - a custom module for Kernel::System::Ticket

=head1 PUBLIC INTERFACE

=over 4

=item SendAgentNotification()

send an agent notification via email

    my $Success = $TicketObject->SendAgentNotification(
        TicketID    => 123,
        CustomerMessageParams => {
            SomeParams => 'For the message!',
        },
        Type        => 'Move', # notification types, see database
        RecipientID => $UserID,
        UserID      => 123,
    );

Events:
    ArticleAgentNotification

=cut

sub Kernel::System::Ticket::SendAgentNotification {
    my ( $Self, %Param ) = @_;

    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');
    my $UserObject   = $Kernel::OM->Get('Kernel::System::User');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # check needed stuff
    for my $Needed (qw(CustomerMessageParams TicketID Type RecipientID UserID)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );
            return;
        }
    }

    # return if no notification is active
    return 1 if $Self->{SendNoNotification};

    # Check if agent receives notifications for actions done by himself.
    if ( !$ConfigObject->Get('AgentSelfNotifyOnAction') && ( $Param{RecipientID} eq $Param{UserID} ) ) {
        return 1;
    }

    # compat Type
    if (
        $Param{Type}
        =~ /(EmailAgent|EmailCustomer|PhoneCallCustomer|WebRequestCustomer|SystemRequest)/
        )
    {
        $Param{Type} = 'NewTicket';
    }

    # get recipient
    my %User = $UserObject->GetUserData(
        UserID => $Param{RecipientID},
        Valid  => 1,
    );

    # check recipients
    return if !$User{UserEmail};
    return if $User{UserEmail} !~ /@/;

    # get ticket object to check state
    my %Ticket = $Self->TicketGet(
        TicketID      => $Param{TicketID},
        DynamicFields => 0,
    );

# ---
# Perl-Services
# ---
    my @SuppressTypes = @{ $ConfigObject->Get( 'Responsible::SuppressTypes' ) || [] };
    if ( ( first { $Param{Type} eq $_ }@SuppressTypes ) && $ConfigObject->Get( 'Ticket::Responsible' ) ) {
        if ( $Ticket{ResponsibleID} == $Param{RecipientID} && $Ticket{OwnerID} != $Param{RecipientID} ) {
            return 1;
        }
    }
# ---

    if (
        $Ticket{StateType} eq 'closed' &&
        $Param{Type} eq 'NewTicket'
        )
    {
        return;
    }

    my $TemplateGeneratorObject = $Kernel::OM->Get('Kernel::System::TemplateGenerator');
    my $SendmailObject          = $Kernel::OM->Get('Kernel::System::Email');

    my %Notification = $TemplateGeneratorObject->NotificationAgent(
        Type                  => $Param{Type},
        TicketID              => $Param{TicketID},
        CustomerMessageParams => $Param{CustomerMessageParams},
        RecipientID           => $Param{RecipientID},
        UserID                => $Param{UserID},
    );

    # send notify
    $SendmailObject->Send(
        From => $ConfigObject->Get('NotificationSenderName') . ' <'
            . $ConfigObject->Get('NotificationSenderEmail') . '>',
        To       => $User{UserEmail},
        Subject  => $Notification{Subject},
        MimeType => $Notification{ContentType} || 'text/plain',
        Charset  => $Notification{Charset},
        Body     => $Notification{Body},
        Loop     => 1,
    );

    # write history
    $Self->HistoryAdd(
        TicketID     => $Param{TicketID},
        HistoryType  => 'SendAgentNotification',
        Name         => "\%\%$Param{Type}\%\%$User{UserEmail}",
        CreateUserID => $Param{UserID},
    );

    # log event
    $LogObject->Log(
        Priority => 'info',
        Message  => "Sent agent '$Param{Type}' notification to '$User{UserEmail}'.",
    );

    # event
    $Self->EventHandler(
        Event => 'ArticleAgentNotification',
        Data  => {
            TicketID => $Param{TicketID},
        },
        UserID => $Param{UserID},
    );

    return 1;
}

sub Kernel::System::Ticket::ArticleCreate {
    my ($Self, %Param) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    my @SuppressTypes = @{ $ConfigObject->Get( 'Responsible::MuteTypes' ) || [] };
    if (
        ( first { $Param{HistoryType} eq $_ }@SuppressTypes ) &&
        $ConfigObject->Get( 'Ticket::Responsible' )
    ) {
        my %Ticket = $Self->TicketGet(
            TicketID      => $Param{TicketID},
            DynamicFields => 0,
        );

        if ( $Param{ForceNotificationToUserID} && ref $Param{ForceNotificationToUserID} ne 'ARRAY' ) {
            $Param{ForceNotificationToUserID} = [ $Param{ForceNotificationToUserID} ];
        }

        if ( $Param{ExcludeNotificationToUserID} && ref $Param{ExcludeNotificationToUserID} ne 'ARRAY' ) {
            $Param{ExcludeNotificationToUserID} = [ $Param{ExcludeNotificationToUserID} ];
        }

        if ( !( first { $_ == $Ticket{ResponsibleID} }@{$Param{ForceNotificationToUserID} || []} ) ) {
            push @{ $Param{ExcludeNotificationToUserID} }, $Ticket{ResponsibleID};
        }
    }

    $Self->Kernel::System::Ticket::Article::ArticleCreate( %Param );
}

1;

=back

=head1 TERMS AND CONDITIONS

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
