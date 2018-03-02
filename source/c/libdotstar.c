#include "libdotstar.h"
#include <stdlib.h>
#include <string.h>

void printData(const char* location, struct Spi* spi, unsigned char* pixels, uint32_t nrOfPixels) {
  printf("%s: %p, %d\n", location, spi, nrOfPixels);
  unsigned char* p = (unsigned char*)pixels;
  for (int i=0; i<nrOfPixels; i++) {
    printf("0x%02x%02x%02x%02x ", p[4*i], p[4*i+1], p[4*i+2], p[4*i+3]);
  }
  printf("\n");
}

#ifdef REAL_SPI
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/ioctl.h>

struct Spi* createSpi() {
  struct Spi* spi = (struct Spi*)malloc(sizeof(struct Spi));
  memset(spi, 0, sizeof(struct Spi));

  spi->transfer[0].len = 4;
  spi->transfer[0].bits_per_word = 8;
  spi->transfer[1].bits_per_word = 8;
  spi->transfer[2].bits_per_word = 8;

  const char* SPI_DEV = "/dev/spidev0.0";
  spi->file = open(SPI_DEV, O_RDWR);
  if (spi->file < 0) {
    fprintf(stderr, "cannot open %s\n", SPI_DEV);
    goto error;
  }
  fprintf(stderr, "opened spi device\n");
  uint8_t mode = SPI_MODE_0 | SPI_NO_CS;
  int res = ioctl(spi->file, SPI_IOC_WR_MODE, &mode);
  if (res != 0) {
    fprintf(stderr, "cannot set spi to write: ioctl failed with %d\n", res);
    goto error;
  }
  fprintf(stderr, "spi in write mode\n");

  res = ioctl(spi->file, SPI_IOC_WR_MAX_SPEED_HZ, BITRATE);
  res = 0;
  if (res != 0) {
    fprintf(stderr, "cannot set spi speed: ioctl failed with %d\n", res);
    goto error;
  }
  fprintf(stderr, "set speed of spi\n");

  return spi;

 error:
  if (spi->file) {
    close(spi->file);
  }
  free(spi);
  return 0;
}

void destroySpi(struct Spi* spi) {
  if (spi->file) {
    close(spi->file);
  }
  free(spi);
}

int writeSpi(struct Spi* spi, unsigned char* pixels, uint32_t nrOfPixels) {
  //  printData(__FUNCTION__, spi, pixels, nrOfPixels);
  spi->transfer[0].speed_hz = BITRATE;
  spi->transfer[1].speed_hz = BITRATE;
  spi->transfer[2].speed_hz = BITRATE;
  spi->transfer[1].tx_buf = (unsigned long)pixels;
  spi->transfer[1].len = nrOfPixels * 4;
  spi->transfer[2].len = (nrOfPixels + 15) / 16;
  int res = ioctl(spi->file, SPI_IOC_MESSAGE(3), spi->transfer);
  res = 0;
  if (res != 0) {
    return 1;
  }
  return 0;
}
#endif

#ifdef SIM_SPI
struct Spi* createSpi() {
  struct Spi* spi = (struct Spi*)malloc(sizeof(struct Spi));
  memset(spi, 0, sizeof(struct Spi));
  printf("%s: %p\n", __FUNCTION__, spi);
  return spi;
}

void destroySpi(struct Spi* spi) {
  printf("%s: %p\n", __FUNCTION__, spi);
  free(spi);
}

int writeSpi(struct Spi* spi, unsigned char* pixels, uint32_t nrOfPixels) {
  //  printData(__FUNCTION__, spi, pixels, nrOfPixels);
  return 0;
}
#endif
