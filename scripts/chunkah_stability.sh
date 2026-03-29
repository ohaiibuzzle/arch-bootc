#!/bin/bash

pacman -Qq | while read -r pkgname; do
  echo "Setting file attributes for package: $pkgname (chunkah)"
  pacman -Qlq "$pkgname" | while read -r filepath; do
    if [[ -f "$filepath" ]]; then
       setfattr -n user.component -v "$pkgname" "$filepath" || true
    fi
  done
done