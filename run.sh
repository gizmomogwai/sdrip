#!/bin/bash -xe
sudo swapon /swap || true
PATH=/home/osmc/bin/ldc2-1.5.0-linux-armhf/bin:$PATH exec dub run -- tcpreceiver
