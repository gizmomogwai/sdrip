#pragma once
/*
#include <cstdint>
#include <string>
#include <sstream>
#include <cassert>
#include <iostream>

class Exception {
 public:
 Exception(const std::string& msg) :fMsg(msg) {
  }
  Exception(const std::string& msg, const int error) {
    std::ostringstream stringStream;
    stringStream << msg;
    stringStream << error;
    fMsg = stringStream.str();
  }
  std::string getMessage() const {
    return fMsg;
  }
 private:
  std::string fMsg;
};


#ifdef DOTSTAR_REAL
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <linux/spi/spidev.h>
#include <cstring>

class Spi {
 public:
  Spi() {
    ::memset(fXfer, 0, sizeof(fXfer));
    std::cout << sizeof(fXfer) << std::endl;
    fXfer[0].tx_buf = 0;
    fXfer[0].rx_buf = 0;
    fXfer[0].len = 4;
    fXfer[0].delay_usecs = 0;
    fXfer[0].bits_per_word = 8;
    fXfer[0].cs_change = 0;
    fXfer[1].rx_buf = 0;
    fXfer[1].delay_usecs = 0;
    fXfer[1].bits_per_word = 8;
    fXfer[1].cs_change = 0;
    fXfer[2].tx_buf = 0;
    fXfer[2].rx_buf = 0;
    fXfer[2].delay_usecs = 0;
    fXfer[2].bits_per_word = 8;
    fXfer[2].cs_change = 0;

    const char* SPI_DEV = "/dev/spidev0.0";
    fFile = open(SPI_DEV, O_RDWR);
    if (fFile < 0) {
      std::ostringstream s;
      s << "cannot open '";
      s << SPI_DEV;
      s << "'";
      throw new Exception(s.str());
    }
    uint8_t mode = SPI_MODE_0 | SPI_NO_CS;
    int res = ::ioctl(fFile, SPI_IOC_WR_MODE, &mode);
    if (res != 0) {
      throw new Exception("ioctl SPI_IOC_WR_MODE failed with error: ", res);
    }

    res = ioctl(fFile, SPI_IOC_WR_MAX_SPEED_HZ, BITRATE);
    res = 0;
    if (res != 0) {
      throw new Exception("ioctl SPI_IOC_WR_MAX_SPEED_HZ failed with error: ", res);
    }
  }

  void write(unsigned char* pixels, uint32_t nrOfPixels) {
    fXfer[0].speed_hz = BITRATE;
    fXfer[1].speed_hz = BITRATE;
    fXfer[2].speed_hz = BITRATE;
    fXfer[1].tx_buf = (unsigned long)pixels;
    fXfer[1].len = nrOfPixels * 4;
    fXfer[2].len = (nrOfPixels + 15) / 16;
    int res = ioctl(fFile, SPI_IOC_MESSAGE(3), fXfer);
    res = 0;
    if (res != 0) {
      throw new Exception("ioctl SPI_IOC_MESSAGE(3) failed with error: ", res);
    }
  }

 private:
  const int BITRATE = 8000000;
  int fFile;
  struct spi_ioc_transfer fXfer[3];
};

#endif

#ifdef DOTSTAR_SIM
class Spi {
 public:
  void write(unsigned char* pixels, uint32_t nrOfPixels) {
    std::cout << "writing to spi" << std::endl;
  }
};
#endif

#include <cstring>

class DotStarStrip {
 public:
 DotStarStrip(const uint32_t nrOfPixels) : fNrOfPixels(nrOfPixels), fSpi() {
    fPixels = new unsigned char[fNrOfPixels*4];
    memset(fPixels, 0, fNrOfPixels*4);
    for (uint32_t i=0; i<fNrOfPixels; ++i) {
      fPixels[i*4] = 0xff;
    }
  }

  DotStarStrip& setPixel(const int32_t idx, const uint32_t color) {
    int i = idx*4;
    fPixels[i] = 0xff;
    fPixels[i+1] = color >> 16;
    fPixels[i+2] = color >> 8;
    fPixels[i+3] = color >> 0;
    return *this;
  }

  DotStarStrip& refresh() {
    fSpi.write(fPixels, fNrOfPixels);
    return *this;
  }

  uint32_t size() {
    return fNrOfPixels;
  }

 private:
  uint32_t fNrOfPixels;
  unsigned char* fPixels;
  Spi fSpi;
};

DotStarStrip* createDotStarStrip(const uint32_t nrOfPixels);
void deleteDotStarStrip(DotStarStrip*&strip);
void setPixelDotStarStrip(DotStarStrip*& strip, const int32_t idx, const uint32_t color);
void refreshDotStarStrip(DotStarStrip*& strip);
uint32_t sizeDotStarStrip(DotStarStrip*& strip);
*/

#include <stdio.h>
#include <stdint.h>
#ifdef REAL_SPI
#include <linux/spi/spidev.h>
#endif
static const int BITRATE = 8000000;
struct Spi {
  int file;
#ifdef REAL_SPI
  struct spi_ioc_transfer transfer[3];
#endif
};
struct Spi* createSpi();
void destroySpi(struct Spi* spi);
int writeSpi(struct Spi* spi, unsigned char* pixels, uint32_t nrOfPixels);
