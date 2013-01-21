package BeagleBone::SPI;
use Inline C;
use 5.14.1;
use warnings;
use Carp qw(croak);
use Data::Dumper;

sub new {
    my ($class, %args) = @_;
    my $self = {};
    bless $self, $class;
    return $self;
}

# Method to write an entire buffer of data to the controller
# $bytes should be an array-reference
sub SpiWrite {
    my ($self, $bytes) = @_;
    croak "\$bytes param should be array-ref"
        unless (ref $bytes eq 'ARRAY');

    # Convert byte array into appropriate string:
    my $data = join('', map { pack('C', $_) } @$bytes);

    my $length = scalar(@$bytes);

    my $r = c_spi_write($data, $length);
    # warn "spi_write() returned $r\n";
    return $r;
}

1;
__DATA__
__C__
#include <linux/spi/spidev.h>
#include <linux/types.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <errno.h>
#include <stdio.h>
int c_spi_write(unsigned char* bytes, unsigned int length) {
    int i;
    int fd; // I tested with a persistent filehandle; no real difference.
    int ret;

    // for debugging:
    // for (i=0; i < length; i++) {
    //    printf("%x ", bytes[i]);
    // }
    // printf("\n");

    // See /usr/include/linux/spi/spidev.h for documentation..

    fd = open("/dev/spidev2.0", O_RDWR);
    if (fd == -1) {
        perror("Error opening /dev/spidev2.0");
        exit(2);
    }

    uint8_t bits = 8;
    uint16_t delay = 100;
    // 20 MHz seems to work nicely, but maybe some controllers will want
    // slower speeds? Adjust downwards if you encounter trouble.
    // ran into #$%&ing trouble, set speed to 5mhz -JPW
    uint32_t speed = 5000000;
    // uint8_t tx[4096];
    uint8_t cs = 0;

    struct spi_ioc_transfer tr = {
        .tx_buf = (unsigned long)bytes,
        .rx_buf = NULL,
        .len = length,
        //.delay_usecs = delay,
        //.speed_hz = speed,
        //.bits_per_word = bits,
        //.cs_change = cs,
    };

    ret = ioctl(fd, SPI_IOC_MESSAGE(1), &tr);
    if (ret == -1) {
        perror("failed to send SPI");
        exit(2);
    }
    if (close(fd) == -1) {
        perror("failed to close SPI filehandle");
        exit(2);
    }
    return ret;
}

