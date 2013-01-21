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

#set up some variables for use in Imager
my $font_filename = 'UbuntuMono-R.ttf';
my $font = Imager::Font->new(file=>$font_filename)
  or die "Cannot load $font_filename: ", Imager->errstr;

my $lcd = BeagleBone::SSD1306->new(
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

	#&assignTextsNotRef();
	my $text_hr = &assignTexts();
	#make a copy of the empty image to be written on and then displayed
	my $OLED_image = $blank_image->copy();
	#&drawImageNotref();
	&drawImage($text_hr,$OLED_image);

	$OLED_image->flip(dir=>"vh");
	my $buffer_ref = BeagleBone::SSD1306::Image::imageToBuffer($OLED_image);	
	
	#now write image to screen from the buffer created by imageToBuffer
	my $r = $lcd->writeBulk($buffer_ref);
	
	my $elapsed = Time::HiRes::time - $start;
	print "printed [". $r ."] bytes to screen in ". sprintf("%.3f",$elapsed) ." seconds\n";
	sleep(1);
}

#for testing purposes, writes image to a file.  File type is determined by Imager using the file extension, try 'image.bmp' for example
sub writeToFile{
	my ($filename, $image) = @_;
	$image->write(file=>$filename)	or die 'Cannot save $filename: ', $image->errstr;
}

#returns ref to a hash full of 'key' => [string, x, y, fontsize]
#strings are pulled from various inputs to the BeagleBone
sub assignTexts {

	my $temp_fahrenheit = sprintf("%.1f",&getTMP36_temp()) . "f";
	my $time = 	(localtime)[2] % 12 .":". sprintf("%01d",(localtime)[1]);
	my $gear = sprintf("%1d",$temp_fahrenheit % 6);
	my %result_hash = (
	#expected format is 'key' => [string, x, y, fontsize]
	'line1' => ["Air     77f",2,12,14],
	'line2' => ["Oil    212f",2,24,14],
	'line3' => ["Beagle $temp_fahrenheit",2,36,14],
	'line4' => ["Time   $time",2,48,14],
	'line5' => ["Volts  13.8",2,60,14],
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
         
	
#accept an Imager image and return an array of 8 bit numbers
#should work with 128x64, 128x32, and possibly other SSD1306 variations (128x16? 64x64?)
sub imageToBuffer {

	my $image = shift;
	my $pixel_color = 0;
	my @bits = [];
	my $page = '';
	my @buffer;
	my $x = 0;
	my $y_page = 0;
	my $y_bit = 0;
	
	#loop through pages (height/8) by columns (width). Each page is a vertical row of 8 pixels with LSB at the top.
	for(0..($image->getheight()/8 - 1)){
		$y_page = $_;
		for(0..($image->getwidth()-1)){
			$x = $_;
			for(0..7){
				$y_bit = $_;
				$pixel_color = $image->getpixel('x' => $x,'y' => $y_page*8 + $y_bit) or die "cannot getpixel $x, $y_page *8 + $y_bit on image ", $image->errstr;
				if(($pixel_color->rgba())[0]){
					$bits[$y_bit] = 1;
				}
				else{
					$bits[$y_bit] = 0;
				}
			}
			#take array of bits and convert them to a scalar byte, thusly. (0,0,1,0,0,0,1,0) = (34)
			$page = unpack( 'C',pack('b8',join('',@bits)));
			push(@buffer,$page);
			
		}
		
	}
	return \@buffer;

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
