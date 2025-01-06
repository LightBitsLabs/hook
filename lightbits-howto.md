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
