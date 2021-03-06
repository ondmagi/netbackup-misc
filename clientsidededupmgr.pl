#!/usr/bin/perl
#
# Manage client side dedup settings for multiple clients at once
#
# Author: Andreas Skarmutsos Lindh <andreas@superblock.se>
#

#use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use File::Temp;
use File::Basename;

my $windows_temppath = dirname(__FILE__);

# Check which OS we're running on and adjust the script accordingly
my $operating_system = $^O;
if ($operating_system eq "MSWin32")
{
    if (exists $ENV{'NBU_INSTALLDIR'})
    {
        $installpath = "$ENV{'NBU_INSTALLDIR'}";
        chomp($installpath);
    }
    our $bppllistbin = "\"$installpath\\NetBackup\\bin\\admincmd\\bppllist\"";
    our $bpclientbin = "\"$installpath\\NetBackup\\bin\\admincmd\\bpclient\"";
}
else
{
    my $installpath = "/usr/openv/netbackup";
    our $bppllistbin = $installpath."/bin/admincmd/bppllist";
    our $bpclientbin = $installpath."/bin/admincmd/bpclient";
}

my %opt;
my $getoptresult = GetOptions(\%opt,
    "policy|p=s" => \$policyname,
    "client|c=s" => \$clientopt,
    "set|s=s" => \$setting,
    "help|h|?" => \$help,
);
output_usage() if (not $getoptresult);
output_usage() if ($help);

sub output_usage
{
    my $usage = qq{
Usage: $0 [options]

Options:
    -p | --policy <name>        : Policy with clients to update
    -c | --client <name>        : Client to update
    -s | --set <setting>        : Set client side dedup setting to one of the
                            following: preferclient, clientside, mediaserver, LIST
    -h | --help                 : Show this help

};

    die $usage;
}


# Find clients in selected policy, takes one argument
sub get_clients_in_policy
{
    my $policyname = $_[0];
    my $output = `$bppllistbin $policyname -l`;
    my @out;
    foreach (split("\n", $output))
    {
        if (m/^CLIENT/)
        {
            @p = split /\s+/, $_;
            push(@out, $p[1]);
        }
    }
    return @out;
}

# check if client attributes exists for the given client and decide add/update
sub clientattributes_exists
{
    my $client = $_[0];
    system("$bpclientbin -client $client -l");
    if ($? == -1) {
        die "command failed: $!\n";
    }
    elsif ($? == 0)
    {
        return 0;
    }
    else
    {
        return 1;
    }
}

# set dedup mode for a client, example: set_mode("abc.def.com", "preferclient")
sub set_mode 
{
    # Dedup modes
    my %modes = (
        'mediaserver' => 0,
        'preferclient' => 1,
        'clientside' => 2,
    );

    my $client = $_[0];
    my $mode = $_[1];
    my $mode_n = $modes{$mode};
    my $action_needed;

    if (clientattributes_exists($client) == 0)
    {
        $action_needed = "-update";
    }
    else
    {
        $action_needed = "-add";
    }
    system("$bpclientbin -client $client $action_needed -client_direct $mode_n");
}

sub get_mode
{
    my $client = $_[0];
    my $output = `$bpclientbin -client $client -L`;
    chomp($output);
    foreach my $l (split("\n", $output))
    {
        chomp($l);
        if ($l =~ m/.*Deduplication on the media server or.*/)
        {
            return "mediaserver";
        }
        elsif ($l =~ m/.*Prefer to use client-side deduplication or.*/)
        {
            return "preferclient";
        }
        elsif ($l =~ m/.*Always use client-side deduplication or.*/)
        {
            return "clientside";
        }
    }
    print("Found no info for $client, not added in client attributes\n");
    return "mediaserver";
}

sub main
{
    # figure out which clients to operate on
    my @clients;
    if ($clientopt) # if -c is set, juse use one client
    {
        push(@clients, $clientopt);
    }
    if ($policyname) # if -p is set, policy is specified and we need to fetch all clients
    {
        foreach (get_clients_in_policy($policyname))
        {
            push(@clients, $_);
        }
    }

    # check for -s && figure out what setting to set
    if (!$setting)
    {
        die("You must specify -s option.\n");
    }
    foreach my $client (@clients)
    {
        if ($setting eq "LIST")
        {
            my $m = get_mode($client);
            print("client:$client mode:$m\n");
        }
        else
        {
        set_mode($client, $setting); 
        }
    }
}

main();
