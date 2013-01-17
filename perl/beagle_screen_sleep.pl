#!/usr/bin/perl
#
#shatrat@shatrat.com


use strict;
use BeagleBone::SSD1306;

my $lcd = BeagleBone::SSD1306->new(
    dc_pin => 'P9_15',
    rst_pin => 'P9_23',
  );
  
  $lcd->sleep_command();
  
1;