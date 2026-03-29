#!/bin/bash

pacman -Qq | while read -r pkgname; do
  echo "Setting file attributes for package: $pkgname (chunkah)"
  pacman -Qlq "$pkgname" | while read -r filepath; do
    if [[ -f "$filepath" ]]; then
       setfattr -n user.component -v "$pkgname" "$filepath" || true
    fi
  done
done

# set all of /usr/opt to be owned by the "opt" component, it will be overlayed to /opt in the final image
find /usr/opt -type f -exec setfattr -n user.component -v "opt" {} \; || true