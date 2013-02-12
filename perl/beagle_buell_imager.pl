#!/usr/bin/perl
#
#shatrat@shatrat.com
#
#This script is still a work in progress.
#When complete it should request serial data from my motorcycle ECU, process that data, and display the results to a small display
#eventually I would like to automatically enable the heated grips when the temperature drops below 70
#a GPS module, accelerometer, or other telemetry may also be incorporated
#

use v5.14;
use strict;
use Data::Dumper;
use Imager;
use Time::HiRes;
use BeagleBone::SSD1306::Image;
use Device::SerialPort;
use POSIX;

#open serial connection to ECU

my $serialECU = &openSerialECU();
my @ECU_data = ();


#set up some variables for use in Imager
my $font_filename = 'UbuntuMono-R.ttf';
my $font = Imager::Font->new(file=>$font_filename)
  or die "Cannot load $font_filename: ", Imager->errstr;

my $lcd = BeagleBone::SSD1306::Image->new(
    dc_pin => 'P9_15',
    rst_pin => 'P9_23',
  );

# heat_pin is the GPIO pin which will trigger the heated equipment N-FET
my $heat_pin = BeagleBone::Pins->new('P8_46');
  
#create a blank image of correct resolution
my $blank_image = Imager->new(xsize => 128, ysize => 64, channels=>1, bits=>1);

#initialize my colors. because we are using 1 channel the values are (grayscale,alpha,NA,NA)
my $white_color = Imager::Color->new(255,255,0,0);
my $black_color = Imager::Color->new(0,255,0,0);
#create a white border
$blank_image->box(filled => 1, color => $white_color);
$blank_image->box(xmin => 1, ymin => 1, xmax => 126, ymax => 62, filled => 1, color => $black_color);


my $count = 1;
#loop through fetching info and updating screen
while($count++){

	#get timestamp for ghetto performance monitoring
	my $start = Time::HiRes::time;
	#retrieve data from serial ECU into ECU_data array
	&getDDFIRuntimeData();
	#read values into text_hr
	my $text_hr = &assignTexts();
	#blank the OLED_image
	my $OLED_image = $blank_image->copy();
	#draw values from text_hr into the OLED_image
	&drawImage($text_hr,$OLED_image);

	#my screen is currently mounted upside down. fix it in software.
	$OLED_image->flip(dir=>"vh");
	
	#now write image to screen from the buffer created by imageToBuffer
	my $r = $lcd->display_image($OLED_image);
	
	#now activate the heated grips based on the temp
	&thermostat($count);
	
	my $elapsed = Time::HiRes::time - $start;
	print "printed [". $r ."] bytes to screen in ". sprintf("%.3f",$elapsed) ." seconds\n";
#	sleep(1);
	if($count == 255){
		$count = 1;
	}
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
#	my $gear = sprintf("%1d",$temp_fahrenheit % 6);
	my $gear = &getGearSelection();
	
	my $air_temp = &getIntakeAirTemp();
	my $oil_temp = &getOilTemp();
	my $bat_volts = &getBatVoltg();
	
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

sub getGearSelection{

	my $ratio = ord $ECU_data[100];
	my $gear1 = 42;
	my $gear2 = 61;
	my $gear3 = 81;
	my $gear4 = 98;
	my $gear5 = 115;
	my $g = 'N';
	
  if($gear1 - 5 < $ratio && $ratio < $gear1 + 5)
    {
    	$g = 1;
    }
  elsif($gear2 - 5 < $ratio && $ratio < $gear2 + 5)
    {
    	$g = 2;
    }
  elsif($gear3 - 5 < $ratio && $ratio < $gear3 + 5)
    {
    	$g = 3;
    }
  elsif($gear4 - 5 < $ratio && $ratio < $gear4 + 5)
    {
    	$g = 4;
    }
  elsif($gear5 - 5 < $ratio && $ratio < $gear5 + 5)
    {
    	$g = 5;
    }

  return $g;
	
}

sub getIntakeAirTemp{

	#this is my ghetto way of putting two bytes back together into one integer
	#Please don't put this on the daily WTF
	#TIMTOWTDI right?
	my $temp = (ord($ECU_data[32]))*256 + ord($ECU_data[33]);
	$temp = $temp*0.1 - 40; #convert raw value to temp C
	return sprintf("%1d",$temp*9/5 + 32); #return temp F
	
}

sub getOilTemp{
	#same as Air temp but different bytes
	my $temp = (ord($ECU_data[30]))*256 + ord($ECU_data[31]);
	$temp = $temp*0.1 - 40; #convert raw value to temp C
	return sprintf("%1d",$temp*9/5 + 32); #return temp F
}

sub getBatVoltg{
	
	my $volts = (ord($ECU_data[28]))*256 + ord($ECU_data[29]);
	return $volts * 0.01;
}

sub thermostat{
	my $count = shift;
	my $temp = &getTMP36_temp();
	if ($temp < 50){
		$heat_pin->digitalWrite(1);
		return 1;
	}
	if($temp > 70){
		return 0;
	}
	else{
		$heat_pin->digitalWrite($count % 2);
		return ($count % 2);
	}
	
}



sub openSerialECU{
	#ttyO5 corresponds to UART5
	my $p = Device::SerialPort->new("/dev/ttyO5") or die "could not open ttyO5";
	$p->baudrate(9600);
	$p->databits(8);
	$p->parity("none");
	$p->stopbits(1);
	return $p;
	
	$serialECU->read(255);
	
}

sub getDDFIRuntimeData{
	
	
#	The following is the format of a 9 byte request to the ECU for run time data	
#	0x01; //SOH
#	0x00; //Emittend
#	0x42; //Recipient
#	0x02; //Data Size
#	0xFF; //EOH
#	0x02; //SOT
#	0x43; //Data 1 //0x56 = Get version, 0x43 = Get runttime data
#	0x03; //EOT
#	0xFD; //Checksum
#
#	The response for a DDFI1 or DDFI2 ECU is a 107 byte string following the format describe
#	in section 22.1 of the Buell Tuning Guide v2
#	http://xoptiinside.com/yahoo_site_admin/assets/docs/BuellTuningGuide_EN_V20.24861747.pdf

#	In order to connect to UART5 on the beaglebone the OMAP_MUX has to be set
#	lcd_data8 is uart5_txd and lcd_data9 is uart5_rxd
#	echo 4 > /sys/kernel/debug/omap_mux/lcd_data8
#	echo 24 > /sys/kernel/debug/omap_mux/lcd_data9

	my @request = (0x01, 0x00, 0x42, 0x02, 0xFF, 0x02, 0x43, 0x03, 0xFD);
	
	#get rid of any garbage waiting at the serial port
	$serialECU->read(255);

	#send the request string to the ECU
	foreach my $byte (@request){
		$serialECU->write(map {chr} $byte);			
	}
	
	my $response = '';
	my $timeout = time + 5;
	#read from serial into buffer until buffer is 107 bytes
	while(length($response) < 107) {

		my $new = $serialECU->read(255);
		if($new){
			$response = $response . $new;			
		}
		if(time > $timeout){
			print "serial request timed out waiting for response \n";
			return ();
		}
	}
	
	@ECU_data = split('',$response);
#		print sprintf(" %02X ",ord(@ECU_data[100])) . "\n";
#		print ord(@ECU_data[100]) . "\n";
	}

