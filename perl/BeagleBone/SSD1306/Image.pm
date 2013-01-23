package BeagleBone::SSD1306::Image;
use 5.14.1;
use warnings;
use parent 'BeagleBone::SSD1306';
use Imager;

=head1 NAME

BeagleBone::SSD1306::Image

=head1 SYNOPSIS

Provides subroutines to manipulate and display Imager objects that are useful for SSD1306 monochrome displays

This assumes a grayscale image of the same size as the monochrome display
	Imager->new(xsize => 128, ysize => 64, channels=>1, bits=>1);


=cut

=head2 imageToBuffer

Accept an Imager image and return an array of 8 bit numbers
Was written to work with grayscale Imager objects.
Should work with 128x64, 128x32, and possibly other SSD1306 variations (128x16? 64x64?)

=cut


sub imageToBuffer {
	my $image = shift;
	my $pixel_color = 0;
	my @bits = [0,0,0,0,0,0,0,0];
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
				$pixel_color = $image->getpixel('x' => $x,'y' => $y_page*8 + $y_bit) 
					or die "cannot getpixel $x, $y_page *8 + $y_bit on image ", $image->errstr;
				
				#TODO see if there is a way to read the first channel of color index directly
				#without calling the rgba function and incurring call stack overhead
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
			#TODO instead of using push, rewrite to use $buffer[$y_page*$image->getwidth() + $x] = $page;
			#because writing to a fixed size array is faster than pushing to one
			#also call getwidth and getheight once and store the value
		}
		
	}
	return \@buffer;

}

1;
