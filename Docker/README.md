# Docker image for running Dextool on Ubuntu

## Mac OS

### Giving permissions to access shared folder

The path /opt/Dextool-ubuntu-docker-shared is not shared from OS X and is not known to Docker.
You can configure shared paths from Docker -> Preferences... -> File Sharing.
See https://docs.docker.com/docker-for-mac/osxfs/#namespaces for more info.

# Credit

This docker image is derived from the mull project.
[mull](hhttps://github.com/mull-project/mull)
