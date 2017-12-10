#!/bin/bash -xe
sudo swapon /swap || true
PATH=/home/osmc/bin/ldc/bin:$PATH exec dub run -- tcpreceiver
