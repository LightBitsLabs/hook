#!/bin/bash

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <VMLINUZ_PATH> <INITRAMFS_PATH>"
    exit 1
fi

VMLINUZ_PATH=$1
INITRAMFS_PATH=$2

if [ ! -f "$VMLINUZ_PATH" ]; then
    echo "VMLINUZ file not found at $VMLINUZ_PATH"
    exit 1
fi

if [ ! -f "$INITRAMFS_PATH" ]; then
    echo "INITRAMFS file not found at $INITRAMFS_PATH"
    exit 1
fi


GIT_VERSION=$(git describe --tags --abbrev=8 --always --long --dirty)

REPO_NAME=tink-boot
ARGS="--username admin --password password --base-url https://pulp03.lab.lightbitslabs.com"

if [ -z "$(pulp $ARGS file repository show --name $REPO_NAME)" ]
then
    echo "Creating the repository"
    pulp $ARGS file repository create --name $REPO_NAME --autopublish
fi

REMOVE_CONTENT=$(pulp $ARGS file repository content list --repository $REPO_NAME |jq -c '[.[]|{"relative_path":.relative_path, "sha256":.sha256}]')
echo "Content to be removed" $REMOVE_CONTENT

ADD_CONTENT='['

for file in "$VMLINUZ_PATH" "$INITRAMFS_PATH"
do
    SMEE_FILE_PATH=$file
    ARTIFACT_SHA256=$(sha256sum $SMEE_FILE_PATH | cut -d' ' -f1)
    ARTIFACT_HREF=$(pulp $ARGS artifact upload --file $SMEE_FILE_PATH | jq -r '.pulp_href')
    pulp $ARGS artifact show --href $ARTIFACT_HREF
    ARTIFACT_BASENAME=$(basename "$file")
    CONTENT_HREF=$(pulp $ARGS file content create --relative-path "$ARTIFACT_BASENAME" --sha256 $ARTIFACT_SHA256 | jq -r '.pulp_href')
    pulp $ARGS file content show --href $CONTENT_HREF
    ADD_CONTENT+=$(echo {'"sha256":''"'$ARTIFACT_SHA256'"'',''"relative_path":''"'$ARTIFACT_BASENAME'"'},)
done
ADD_CONTENT=${ADD_CONTENT:0:-1}
ADD_CONTENT+=']'
echo "Content to be added" $ADD_CONTENT

echo "Updating repository"
pulp $ARGS file repository content modify --repository $REPO_NAME --remove-content $REMOVE_CONTENT --add-content $ADD_CONTENT
echo "Repository version"
pulp $ARGS file repository version show --repository $REPO_NAME

if [ "$(pulp $ARGS file publication list --repository $REPO_NAME | jq '. | length')" -eq 0 ]
then
    echo "Creating publication"
    PUBLICATION_HREF=$(pulp $ARGS file publication create --repository $REPO_NAME --version 1 | jq -r '.pulp_href')
    echo "Publication href"
    pulp $ARGS show --href $PUBLICATION_HREF
else
    PUBLICATION_HREF=$(pulp $ARGS file publication list --repository $REPO_NAME| jq -r '.[0].pulp_href')
    echo "Publication href"
    pulp $ARGS show --href $PUBLICATION_HREF
fi

if [ "$(pulp $ARGS file distribution list --name $REPO_NAME | jq '. | length')" -eq 0 ]
then
    echo "Creating new distribution"
    pulp $ARGS file distribution create --name $REPO_NAME --base-path "$REPO_NAME" --publication $PUBLICATION_HREF --labels '{"version": "'$GIT_VERSION'"}'
    pulp $ARGS file distribution show --name $REPO_NAME
else
    echo "Updating distribution"
    pulp $ARGS file distribution update --name $REPO_NAME --repository $REPO_NAME --labels '{"version": "'$GIT_VERSION'"}'
    pulp $ARGS file distribution show --name $REPO_NAME
fi
