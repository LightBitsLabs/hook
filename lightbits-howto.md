## howto build image

for building the hook image we have the following options:

```bash
./build.sh kernel hook-latest-lts-amd64
```

```bash
./build.sh build hook-latest-lts-amd64
```

the products will be placed at: `out/hook/`

in order to build the images with sshd support should run the following:

```bash
./build.sh debug hook-latest-lts-amd64
```

## Upload images to pulp:

First we would need to rename the files to the following format:

```bash
mv out/hook/initramfs-latest-lts-x86_64 out/hook/initramfs-x86_64
mv out/hook/vmlinuz-latest-lts-x86_64 out/hook/vmlinuz-x86_64 
```

Then use the following script to upload to pulp these 2 images and override the tink-boot entry:

```bash
./scripts/smee-to-pulp.sh out/hook/vmlinuz-x86_64 out/hook/initramfs-x86_64
```

files will be placed at: `https://pulp03.lab.lightbitslabs.com/pulp/content/tink-boot/`
