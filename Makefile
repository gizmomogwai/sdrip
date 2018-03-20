all:
	mkdir -p out/main/raspi
	arm-linux-gnueabihf-gcc -std=c11 -mhard-float -DREAL_SPI=1 -c source/c/libdotstar.c -o out/main/raspi/libdotstar.o
	arm-linux-gnueabihf-ar rcs out/main/raspi/libdotstar.a out/main/raspi/libdotstar.o
