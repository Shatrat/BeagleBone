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

=head2 display_image

Accept an Imager object and send it to the SSD1306 display

=cut

sub display_image{
my ($self, $image) = @_;
my $buffer = &imageToBuffer($image);
return $self->writeBulk($buffer);;
}


=head2 imageToBuffer

Accept an Imager image and return an array of 8 bit numbers
Was written to work with grayscale Imager objects.  It will work with any Imager object, but you might not get the results you expect.
Should work with 128x64, 128x32, and possibly other SSD1306 variations (128x16? 64x64?)

=cut


sub imageToBuffer {
	my $image = shift;
	my $pixel_color = 0;
	my @bits = [0,0,0,0,0,0,0,0];
	my $page = '';
	my $x = 0;
	my $y_page = 0;
	my $y_bit = 0;
	my $width = $image->getwidth();
	my $height = $image->getheight();
	#create the buffer as already being the correct size to speed things up inside the loop
	my @buffer = (0) x ($width*$height/8);
	
	
	#loop through pages (height/8) by columns (width). Each page is a vertical row of 8 pixels with LSB at the top.
	for(0..($height/8 - 1)){
		$y_page = $_;
		for(0..($width-1)){
			$x = $_;
			for(0..7){
				$y_bit = $_;
				$pixel_color = $image->getpixel('x' => $x,'y' => $y_page*8 + $y_bit) 
					or die "cannot getpixel $x, $y_page *8 + $y_bit on image ", $image->errstr;

				$bits[$y_bit] = 0;
				if(($pixel_color->rgba())[0]){
					$bits[$y_bit] = 1;
				}

			}
			#take array of bits and convert them to a scalar byte, thusly. (0,0,1,0,0,0,1,0) = (34)
			$page = unpack( 'C',pack('b8',join('',@bits)));
			$buffer[$y_page*$width + $x] = $page;
		}
		
	}
	return \@buffer;

}

1;
