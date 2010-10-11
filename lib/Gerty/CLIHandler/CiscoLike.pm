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

# Command-line interface for Cisco-like devices


package Gerty::CLIHandler::CiscoLike;
use base qw(Gerty::CLIHandler::Generic);

use strict;
use warnings;
use Expect qw(exp_continue);


my %supported_actions =
    ('config-backup' => 'config_backup');

    

     
sub new
{
    my $proto = shift;
    my $options = shift;
    my $class = ref($proto) || $proto;
    
    my $self = $class->SUPER::new( $options );
    return undef unless defined($self);

    my $sysname = $self->{'device'}->{'SYSNAME'};

    my $admin_already = $self->check_admin_mode();
    if( $admin_already )
    {
        $self->{'prompt'} = $self->{'admin-prompt'};
    }

    if( not $self->init_terminal() )
    {
        $Gerty::log->error
            ('Failed to initialize terminal for ' . $sysname);
        return undef;
    }
    
    
    if( (not $admin_already) and $self->{'admin-mode'} )
    {
        my $epasswd = $self->device_attr('cli-auth-epassword');
        if( not defined( $epasswd ) )
        {
            $Gerty::log->error
                ('Missing attribute "cli-auth-epassword" for ' . $sysname);
            return undef;
        }
        
        if( not $self->set_admin_mode( $epasswd ) )
        {
            $Gerty::log->error
                ('Failed to switch into enable mode for ' . $sysname);
            return undef;
        }

        $self->{'prompt'} = $self->{'admin-prompt'};
    }
        
    return $self;
}



sub check_admin_mode
{
    my $self = shift;

    my $exp = $self->{'expect'};
    my $admin_mode = 0;
    
    $exp->send("\r");    
    $exp->expect
        ( $self->{'cli-timeout'},
          ['-re', $self->{'admin-prompt'}, sub {$admin_mode = 1}],
          ['-re', $self->{'user-prompt'}],          
          ['timeout'],
          ['eof']);
    
    return $admin_mode;
}
    



sub init_terminal
{
    my $self = shift;

    my @cmd;
    foreach my $item (split(/\s*,\s*/o,
                               $self->device_attr('init-terminal')))
    {
        my $command = $self->device_attr($item . '-command');
        if( defined($command) )
        {
            push(@cmd, $command);                
        }
        else
        {
            $Gerty::log->error('"init-terminal" lists ' . $item .
                               ', but the attribute ' .
                               $item . '-command is not defined for device ' .
                               $self->{'device'}->{'SYSNAME'});
            return undef;
        }
    }

    foreach my $command ( @cmd )
    {
        if( not $self->exec_command($command) )
        {
            return undef;
        }
    }
    
    return 1;
}


    



sub set_admin_mode
{
    my $self = shift;
    my $epasswd = shift;

    my $exp = $self->{'expect'};
    my $sysname = $self->{'device'}->{'SYSNAME'};
    my $enablecmd = $self->device_attr('admin-mode-command');
    my $failure;

    $Gerty::log->debug('Setting admin mode for ' . $sysname);

    $exp->send($enablecmd . "\r");    
    my $result = $exp->expect
        ( $self->{'cli-timeout'},
          ['-re', qr/password:/i, sub {
              $exp->send($epasswd . "\r"); exp_continue;}],
          ['-re', $self->{'admin-prompt'}],
          ['-re', $self->{'user-prompt'}, sub {
              $failure = 'Access denied'}],          
          ['timeout', sub {$failure = 'Connection timeout'}],
          ['eof', sub {$failure = 'Connection closed'}]);
    
    if( not $result )
    {
        $Gerty::log->error
            ('Could not match the output for ' .
             $sysname . ': ' . $exp->before());            
        return undef;
    }
    
    if( defined($failure) )
    {
        $Gerty::log->error
            ('Failed switching to admin mode for ' .
             $sysname . ': ' . $failure);
        return undef;
    }

    return 1;
}




sub supported_actions
{
    my $self = shift;

    my $ret = [];
    push(@{$ret}, keys %supported_actions);
    push(@{$ret}, @{$self->SUPER::supported_actions()});

    return $ret;
}


sub do_action
{
    my $self = shift;    
    my $action = shift;

    if( defined($supported_actions{$action}) )
    {
        my $method = $supported_actions{$action};
        return $self->$method($action);
    }

    return $self->SUPER::do_action($action);
}



sub config_backup
{
    my $self = shift;    

    my $cmd = $self->device_attr('show-config-command');
    if( not defined($cmd) )
    {
        $Gerty::log->error
            ('Missing parameter show-config-command for ' .
             $self->{'device'}->{'SYSNAME'});
        return undef;
    }

    my $ret = $self->exec_command( $cmd );

    my $excl = $self->device_attr('config-exclude');
    if( defined($excl) )
    {
        foreach my $pattern_name (split(/\s*,\s*/o, $excl))
        {
            my $regexp = $self->device_attr($pattern_name . '-regexp');
            if( defined($regexp) )
            {
                $ret =~ s/$regexp//m;
            }
            else
            {
                $Gerty::log->error
                    ('config-exclude points to ' . $pattern_name .
                     ', but parameter ' . $pattern_name .
                     '-regexp is not defined for ' .
                     $self->{'device'}->{'SYSNAME'});
            }
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
