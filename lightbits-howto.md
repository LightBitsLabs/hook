
## Building OSIE

There are two ways to build an OSIE (hook) image:

### Build env using docker

One time build of a builder-image containing prerequisits:

```bash
docker buildx build --load -t hook-nix-dev -f hack/Dockerfile .
```

Run a container from `hook` directory:

```bash
docker run -it --rm -v "$PWD:$PWD" -w "$PWD" -v /var/run/docker.sock:/var/run/docker.sock hook-nix-dev bash
```

Inside the container apply these two commands to enter nix-shell and config git:

```bash
nix-shell
git config --global --add safe.directory "$PWD"
```

Issue following commands to build


```bash
# for release
make TAG=$(git rev-parse --short HEAD) dist
# for debug
make TAG=$(git rev-parse --short HEAD) dbg-dist
```

```bash
# build hook-docker images
nix-shell --run 'make TAG=$(git rev-parse --short HEAD) dist'
# build debug version.
nix-shell --run 'make TAG=$(git rev-parse --short HEAD) dbg-dist'
```

### Setup Environment (more involved process)

[embedmd]:#(./setup-build-env.sh)
```sh
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

```


## clearing linuxkit cache (ref: https://github.com/linuxkit/linuxkit/issues/3634)

Sometime we want to clear from the cache of linuxkit the services it downloaded as OCI images
by issuing the following command:

```bash
linuxkit cache ls
```

we will see all the cached images and we can delete them one by one...

## Updating/Building a custom kernel

Sometimes we would want to build a new kernel since we want to enable some flags
or upgrade it.

The following can be found at the readme of `tinkerbell/hook/kernel` repository.

The fillowing example will build a patched kernel:

As you can see it will only build the kernel but will not push it since we are building
a `devbuild` other builds will push the kernel, by defaul to ORG which is quey.io/tinkerbell

Since we don't have access to this repo to upload data we would need to push it to our repository.

```bash
make devbuild_5.10.x -j4 ORG=docker.lightbitslabs.com/lb-dev-playground KERNEL_PLATFORMS=linux/amd64
```
