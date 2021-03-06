#!/usr/bin/perl -w
BEGIN{
    my $ROOT = '/data/www/html/nw2006/edgedb/cgi/src';
    unshift(@INC, "$ROOT/bioperl/bioperl-1.5.2-RC3");
    unshift(@INC, "$ROOT/CPAN-JMS");;
    unshift(@INC, "$ROOT/TagAS2/modules");
    unshift(@INC, "$ROOT/ensembl/ensembl_main/ensembl/modules");
}

use strict;
use CGI qw(:standard);
use CGI::Carp qw(warningsToBrowser fatalsToBrowser);

my $query = new CGI;

my $clear = param('clear');
my $names = param('add');

my $name_hash = {};

my $old_names = $query->cookie('EEDB_subnet_gene_list');
if($old_names) { 
  my @toks = split/,/, $old_names;
  foreach my $nm (@toks) { $name_hash->{$nm}=1; }
}
if($clear) { $name_hash = {}; }
if($names) { 
  my @toks = split/,/, $names;
  foreach my $nm (@toks) { $name_hash->{$nm}=1; }
}

my $new_names = join ',', sort(keys(%$name_hash));
if($clear) { $new_names=''; }


my $cookie = $query->cookie(-name=>'EEDB_subnet_gene_list',
			 -value=>$new_names,
			 -expires=>'+24h',
			 -path=>'/');
print $query->header(-cookie=>$cookie);
print $query->start_html('My cookie_test.cgi program');

printf("<h3>EEDB_subnet_gene_list</h3>");
printf("<p>old_names  :: %s\n", $old_names) if($old_names);
printf("<p>names      :: %s\n", $names) if($names);
printf("<p>new_names  :: %s\n", $new_names);
print $query->end_html;


