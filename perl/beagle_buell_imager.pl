#!/usr/bin/perl
#
#shatrat@shatrat.com
#GPLv2 or later
#
#Basic sequence (hopefully)
#init {create image template, check everything to make sure it's working}
#loop
#	TODO: request serial data
#	TODO: rx serial data
#	generate text
#	draw text onto copy of blank image
#	traverse image pixels to get binary representation
#	send binary representation to 1306 chip via perl module
#	check GPIO to make sure bike is still running (if not init 0)
#	sleep just so we don't completely peg the little ARM cpu
#

use strict;
use Data::Dumper;
use Imager;
use Time::HiRes;
use BeagleBone::SSD1306::Image;
use Device::SerialPort;
use POSIX;

#set up some variables for use in Imager
my $font_filename = 'UbuntuMono-R.ttf';
my $font = Imager::Font->new(file=>$font_filename)
  or die "Cannot load $font_filename: ", Imager->errstr;

my $lcd = BeagleBone::SSD1306::Image->new(
    dc_pin => 'P9_15',
    rst_pin => 'P9_23',
  );
  
  
#create a blank image of correct resolution
my $blank_image = Imager->new(xsize => 128, ysize => 64, channels=>1, bits=>1);

#initialize my colors. because we are using 1 channel the values are (grayscale,alpha,NA,NA)
my $white_color = Imager::Color->new(255,255,0,0);
my $black_color = Imager::Color->new(0,255,0,0);
#create a white border
$blank_image->box(filled => 1, color => $white_color);
$blank_image->box(xmin => 1, ymin => 1, xmax => 126, ymax => 62, filled => 1, color => $black_color);


#loop through fetching info and updating screen
while(1){
	#get timestamp for ghetto performance monitoring
	my $start = Time::HiRes::time;
	
	my $text_hr = &assignTexts();
	my $OLED_image = $blank_image->copy();
	&drawImage($text_hr,$OLED_image);

	#my screen is currently mounted upside down. meh, fix it in software.
	$OLED_image->flip(dir=>"vh");
	
	#now write image to screen from the buffer created by imageToBuffer
	my $r = $lcd->display_image($OLED_image);
	
	my $elapsed = Time::HiRes::time - $start;
	print "printed [". $r ."] bytes to screen in ". sprintf("%.3f",$elapsed) ." seconds\n";
#	sleep(1);
}

#for testing purposes, writes image to a file.  File type is determined by Imager using the file extension, try 'image.bmp' for example
sub writeToFile{
	my ($filename, $image) = @_;
	$image->write(file=>$filename)	or die 'Cannot save $filename: ', $image->errstr;
}

#returns ref to a hash full of 'key' => [string, x, y, fontsize]
#strings are pulled from various inputs to the BeagleBone
sub assignTexts {

	my $temp_fahrenheit = sprintf("%.1f",&getTMP36_temp());
	my $time = strftime("%I:%M %p", localtime);
	my $gear = sprintf("%1d",$temp_fahrenheit % 6);
	my $air_temp = 77;
	my $oil_temp = 212;
	my $bat_volts = 13.8;
	
	my %result_hash = (
	#expected format is 'key' => [string, x, y, fontsize]
	'line1' => ["Air     ".$air_temp."f",2,12,14],
	'line2' => ["Oil    ".$oil_temp."f",2,24,14],
	'line3' => ["Bone  ".$temp_fahrenheit."f",2,36,14],
	'line4' => ["$time",2,48,14],
	'line5' => ["12VDC  ".$bat_volts."v",2,60,14],
	'gear' => ["$gear",88,52,72],
	);
	return \%result_hash;

}
 
#accepts a ref to a hash full of 'key' => [string, x, y, fontsize]
#and an image onto which we will draw them
sub drawImage {           
	my ($text_hr, $image) = @_;
	
	foreach my $line (keys %$text_hr) {
		my ($string,$x,$y,$font_size)= @{$text_hr->{$line}};
		$image->string(x => $x, y => $y,
			string => $string,
			font => $font,
			size => $font_size,
		 	aa => 0,
			color => $white_color);
	}
} 
         
sub getTMP36_temp{
	#AIN2 in software is AIN1 in hardware, jumper accordingly
	my $ADC_source = '/sys/devices/platform/omap/tsc/ain2';
	open( my $adc_fh, "<", $ADC_source ) || die "Can't open $ADC_source: $!";	
	my $digital_reading = <$adc_fh>;
	close $adc_fh;
	
	#reading/4095 * 1800 returns millivolts for the beaglebone ADC
	#(millivolts - 500) /10 returns degrees C for TMP36 chip
	#Then convert from C to F
	return ((($digital_reading/4095)*1800-500)/10)*9/5 + 32;
	
}

sub getDDFIRuntimeData{
	
	
#	The following is the format of an 8 byte request to the ECU for run time data	
#	inArray[0]=0x01; //SOH
#	inArray[1]=0x00; //Emittend
#	inArray[2]=0x42; //Recipient
#	inArray[3]=0x02; //Data Size
#	inArray[4]=0xFF; //EOH
#	inArray[5]=0x02; //SOT
#	inArray[6]=0x43; //Data 1 //0x56 = Get version, 0x43 = Get runttime data
#	inArray[7]=0x03; //EOT
#	inArray[8]=0xFD; //Checksum
#
#	The response for a DDFI2 ECU is a 107 byte string following the format describe
#	in section 22.1 of the Buell Tuning Guide v2
#	http://xoptiinside.com/yahoo_site_admin/assets/docs/BuellTuningGuide_EN_V20.24861747.pdf

	
}
