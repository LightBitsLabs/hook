#!/usr/bin/env bash

# setup env
sudo apt-get update -y
sudo apt-get install -y qemu-user-static
sudo apt-get install -y docker-buildx-plugin

# NOTE:!!! this part must be run interactivly cause it will ask some questions!!!!!!
sh <(curl -L https://nixos.org/nix/install) --daemon
nix-shell -p nix-info --run "nix-info -m"
sudo apt install nix-bin -y
nix-shell --command true
nix-shell --run .github/workflows/formatters-and-linters.sh
sudo apt install python3-pip -y
python3 -m pip install --upgrade pip
echo ::set-output name=short::$(git rev-parse --short HEAD)
sudo mount -o remount,size=3G /run/user/1001 || true
