# Immich Server

These are some useful commands.
Check more at [Immich Docs](https://immich.app/docs/overview/welcome).

### Docker files locations
`/opt/stacks/immich/`


## Start containers

`docker compose up -d`

## Upgrade (DANGER - check breaking changes)

`docker compose pull & docker compose up -d`

## Library location

It's a SMB share mounted using /etc/fstab:

`//10.0.0.3/photos /mnt/photos cifs credentials=/etc/smb-credentials/photos,iocharset=utf8,vers=3.0,rw,nofail,uid=1000,gid=1000,file_mode=0664,dir_mode=0775 0 0`

Credentials are stored here in a file:

`/etc/smb-credentials/photos`