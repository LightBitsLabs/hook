## Build hwinfo container image

```bash
cd images/hwinfo
REGISTRY=docker.lightbitslabs.com/lb-dev-playground make build-image push-image
```

## Build vmlinuz and initramfs images

For building the hook image we have the following options:

```bash
./build.sh kernel hook-latest-lts-amd64
```

```bash
./build.sh build hook-latest-lts-amd64
```

The products will be placed at: `out/hook/`

In order to build the images with sshd support should run the following:

> NOTE:
>
> Since we don't have versioning today to hwinfo image (we use latest) the
image is in the cache of the nix and will not be pulled every time.
> till we fix the version issue we will need to clear the cache and run
> build/debug again every time.
> The flow looks like this:
>
> ```bash
# look for the specific blob in cache:
cat cache/linuxkit/index.json | grep -C3 hwinfo
         "size": 2835,
         "digest": "sha256:f415c9cced6d890d227ebd43fd11572377b4d6ded7e1d75d3b6fa01147ef0581",
         "annotations": {
            "org.opencontainers.image.ref.name": "docker.lightbitslabs.com/lb-dev-playground/hwinfo:latest"
         }

# remove the layer we want to replace:
rm -rf cache/linuxkit/blobs/sha256/f415c9cced6d890d227ebd43fd11572377b4d6ded7e1d75d3b6fa01147ef0581
```

Building the image with debug enabled:

```bash
./build.sh debug hook-latest-lts-amd64
```

## Upload images to pulp

First we would need to rename the files to the following format:

```bash
mv out/hook/initramfs-latest-lts-x86_64 out/hook/initramfs-x86_64
mv out/hook/vmlinuz-latest-lts-x86_64 out/hook/vmlinuz-x86_64
```

Then use the following script to upload to pulp these 2 images and override the `tinkerbell/hook` entry:

```bash
export PULP_USERNAME=admin
export PULP_PASSWORD=password
export PULP_BASE_URL=https://pulp04.kube02.lab.lightbitslabs.com

./scripts/smee-to-pulp.sh \
    --username $PULP_USERNAME \
    --password $PULP_PASSWORD \
    --base-url $PULP_BASE_URL \
    out/hook/vmlinuz-x86_64 out/hook/initramfs-x86_64
```

Files will be placed at: `$PULP_BASE_URL/pulp/content/tinkerbell/hook/`
