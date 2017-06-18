#!/usr/bin/env perl

use strict;
use warnings;

use lib '/home/debian/perlwork/mojowork/server/site1/lib/Site1/';
use Inputchk;

use feature 'say';


#my $str = 'soreha  エロアホ';
#my $str = '本日は晴天なり';
my $str = 'アホ';

my $chkobj = Inputchk->new($str);
my $res = $chkobj->string;
#   $email->email;
#say $email->result;
   say "string: $res";

   $chkobj->ngword;
my $resp = $chkobj->result;
   say "$resp";
