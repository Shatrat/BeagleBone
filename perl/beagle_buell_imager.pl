#!/usr/bin/perl
#
#shatrat@shatrat.com
#GPLv2 or later
#For Imager to work correctly with fonts in ubuntu, install Freetype2 and recompile Imager in CPAN
#
#Basic sequence
#init (create blank image, check serial interface)
#loop
#	request serial data
#	read serial data, generate text
#	draw text onto copy of blank image
#	traverse image pixels to get binary representation
#	send binary representation to 1306 chip via perl module
#	check GPIO to make sure bike is still running (if not init 0)
#	usleep 200ms
#

use strict;
use Data::Dumper;
use Imager;
use Time::HiRes;
use BeagleBone::SSD1306;

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

my $OLED_image;
my %text_hash;
my $start;
my $elapsed;
my $buffer_ref;

for(1,1){
#get timestamp for ghetto performance monitoring
	$start = Time::HiRes::time;
	&assignTexts();
#make a copy of the empty image to be written on and then displayed
	$OLED_image = $blank_image->copy();
	&drawImage();
	#&imageToStdout();
	$buffer_ref = &imageToBuffer($OLED_image);
	print "buffer is " . @$buffer_ref . "bytes long\n";
	$lcd->reset_to_origin();
	$lcd->writeBulk($buffer_ref);
	$elapsed = Time::HiRes::time - $start;
	print "printed screen in $elapsed seconds\n";
	sleep (1);
}

sub writeToFile{my $file = 'beaglebuell.bmp';
	$OLED_image->write(file=>$file)	or die 'Cannot save $file: ', $OLED_image->errstr;
}

	
sub assignTexts {

	my $temp_fahrenheit = sprintf("%.1f",&getTMP36_temp()) . "f";
	my $time = 	(localtime)[2] % 12 .":". (localtime)[1];
	%text_hash = (	
	'line1' => ["Air     77f",2,12,14],
	'line2' => ["Oil    212f",2,24,14],
	'line3' => ["Beagle $temp_fahrenheit",2,36,14],
	'line4' => ["Time   $time",2,48,14],
	'line5' => ["Volts  13.8",2,60,14],
	'gear' => ["5",88,52,72],
	);

}
 
sub drawImage {              
	foreach my $line (keys %text_hash) {
		my ($string,$x,$y,$font_size)= @{$text_hash{$line}};
		$OLED_image->string(x => $x, y => $y,
			string => $string,
			font => $font,
			size => $font_size,
		 	aa => 0,
			color => $white_color);
	}
} 


sub imageToStdout{        
##iterate through the pixels, just to check speed
	my $x = 0;
	my $y = 0;
	my $pixel_color = 0;
	my $pixel_bit = 0;
	my @pixel_channels = (0,0,0,0);
	
	for (0..63){
		$y = $_;
		for (0..127){
			$x = $_;
			#get 4 channel color of pixel at x,y
			$pixel_color = $OLED_image->getpixel(x => $x, y => $y);
			@pixel_channels = $pixel_color->rgba();#rgba() is a bit of a misnomer in a grayscale image...however there's no ga__() function
			#desired image is stored in first channel
			#$pixel_bit = $pixel_channels[0];
			#increase value of first channel for testing so image is legible
			if($pixel_channels[0]){
				$pixel_bit = 1;
			}
			else{
				$pixel_bit = 0;
			}
		
			#console print pixel at x,y
			#print "$pixel_bit";
			#if($x==127){
			#	print "\n";
			#}
		}
	
	}
}              


	
#accept an Imager image and return an array of 8 bit numbers
sub imageToBuffer(){

	my $image = shift;
	my $pixel_color = 0;
	my @bits = [];
	my $page = '';
	my @buffer;
	my $x = 0;
	my $y_page = 0;
	my $y_bit = 0;
	
	
	for(0..7){
		$y_page = $_;
		for(0..127){
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

			$page = unpack( 'C',pack('b8',join('',@bits)));
	#		print Dumper($page);
			push(@buffer,$page);
			
		}
		
	}
	return \@buffer;
	
}

sub getTMP36_temp{
	my $ADC_source = '/sys/devices/platform/omap/tsc/ain2';
	open( my $adc_fh, "<", $ADC_source ) || die "Can't open $ADC_source: $!";	
	my $digital_reading = <$adc_fh>;
	close $adc_fh;
	
	return ((($digital_reading/4095)*1800-500)/10)*9/5 + 32;
	
	
	
}
