#  Copyright (C) 2010  Stanislav Sinyagin
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software

# Expect logic for Netconf
# Here the ]]>]]> delimiter and logging is handled


package Gerty::Netconf::Transport::Expect;

use base qw(Gerty::HandlerBase);

use strict;
use warnings;
use Expect qw(exp_continue);
use Date::Format;



my %has =
    ('send_netconf_message'    => 1,
     'receive_netconf_message' => 1);


sub new
{
    my $class = shift;
    my $options = shift;
    my $self = $class->SUPER::new( $options );    
    return undef unless defined($self);
    
    foreach my $attr
        ('netconf.timeout',
         'netconf.log-dir', 'netconf.log-enabled',
         'netconf.logfile-timeformat')
    {
        my $val = $self->device_attr($attr);
        if( not defined($val) )           
        {
            $Gerty::log->error
                ('Missing mandatory attribute "' .
                 $attr . '" for device: ' . $self->sysname);
            return undef;
        }
        $self->{'attr'}{$attr} = $val;        
    }

    $self->{'outstanding_messages'} = [];
    
    return $self;
}



sub close
{
    my $self = shift;

    if( defined($self->{'expect'}) )
    {
        $self->{'expect'}->hard_close();
        undef $self->{'expect'};
    }
}



sub has
{
    my $self = shift;
    my $what = shift;
    return $has{$what};
}
    



# Creates an Expect object and initializes logging
sub open_expect
{
    my $self = shift;

    my $exp = new Expect();
    $exp->raw_pty(1);
    
    if( not $Gerty::expect_debug )
    {
        $exp->log_stdout(0);
    }
    
    if( $self->{'attr'}{'netconf.log-enabled'} )
    {
        my $logdir = $self->{'attr'}{'netconf.log-dir'};
        if( length($logdir) > 0 )
        {
            if( not -d $logdir )
            {
                $Gerty::log->warning
                    ('The directory ' . $logdir .
                     ' is specified as netconf.log-dir ' .
                     ' for ' . $self->sysname . ' does not exist ');
            }
            else
            {
                $exp->log_file
                    (sprintf
                     ('%s/%s.%s.log',
                      $logdir, $self->sysname,
                      time2str($self->{'attr'}{'netconf.logfile-timeformat'},
                               time())));
            }
        }
        else
        {
            $Gerty::log->info
                ('netconf.log-dir is not specified for ' . $self->sysname .
                 ', logging is disabled');
        }
    }

    $self->{'expect'} = $exp;
    return $exp;
}


sub expect
{
    my $self = shift;
    return $self->{'expect'};
}


sub timeout
{
    my $self = shift;
    return $self->{'attr'}{'netconf.timeout'};
}


sub add_outstanding_message
{
    my $self = shift;
    my $msg = shift;

    push( @{$self->{'outstanding_messages'}}, $msg );
}


sub send_netconf_message
{
    my $self = shift;
    my $msg = shift;

    if( $Gerty::debug_level >= 2 )
    {
        $Gerty::log->debug
            ($self->sysname . ': sending Netconf message: ' . $msg);
    }
    
    $self->expect->send($msg . "\n" . ']]>]]>' . "\n");
}



sub receive_netconf_message
{
    my $self = shift;

    my $ret = {'success' => 1, 'msg' => ''};

    if( scalar(@{$self->{'outstanding_messages'}}) )
    {
        $ret->{'msg'} = shift @{$self->{'outstanding_messages'}};
    }
    else
    {
        my $exp = $self->expect;
    
        if( $exp->expect( $self->timeout, ']]>]]>' ) )
        {
            $ret->{'msg'} = $exp->exp_before();
        }
        else
        {
            $ret->{'success'} = 0;
        }
    }

    if( $ret->{'success'} )
    {
        if( $Gerty::debug_level >= 2 )
        {
            $Gerty::log->debug
                ($self->sysname . ': received Netconf message: ' .
                 $ret->{'msg'});
        }
    }

    return $ret;          
}




    

             
1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End: