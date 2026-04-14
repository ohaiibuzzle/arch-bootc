FROM scratch AS ctx

COPY scripts/ /scripts

FROM docker.io/cachyos/cachyos-v3:latest AS base

FROM base AS bootc-builder

RUN pacman -Syu --noconfirm make git rust go-md2man ostree glibc pkgconf

WORKDIR /home/build
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    git clone "https://github.com/bootc-dev/bootc.git" . && \
    make bin install-all DESTDIR=/output

FROM base AS aur-builder

RUN pacman -Sy --noconfirm base-devel sudo git && \
    useradd builder && \
    echo "builder ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    mkdir /built_pkgs/

WORKDIR /tmp

# RUN sudo -u builder git clone https://aur.archlinux.org/libfprint-cs9711-git.git package && \
#     cd package && \
#     sudo -u builder makepkg -s --noconfirm && \ 
#     cp *.tar.zst /built_pkgs/ && \
#     cd ../ && rm -rf package

RUN sudo -u builder git clone https://aur.archlinux.org/visual-studio-code-bin.git package && \
    cd package && \
    sudo -u builder makepkg -s --noconfirm && \ 
    cp *.tar.zst /built_pkgs/ && \
    cd ../ && rm -rf package

FROM base AS system

COPY --from=bootc-builder /output /

# Move everything from `/var` to `/usr/lib/sysimage` so behavior around pacman remains the same on `bootc usroverlay`'d systems
RUN grep "= */var" /etc/pacman.conf | sed "/= *\/var/s/.*=// ; s/ //" | xargs -n1 sh -c 'mkdir -p "/usr/lib/sysimage/$(dirname $(echo $1 | sed "s@/var/@@"))" && mv -v "$1" "/usr/lib/sysimage/$(echo "$1" | sed "s@/var/@@")"' '' && \
    sed -i -e "/= *\/var/ s/^#//" -e "s@= */var@= /usr/lib/sysimage@g" -e "/DownloadUser/d" /etc/pacman.conf

# Remove NoExtract rules, otherwise no additional languages and help pages can be installed
# See https://gitlab.archlinux.org/archlinux/archlinux-docker/-/blob/master/pacman-conf.d-noextract.conf?ref_type=heads
RUN sed -i 's/^[[:space:]]*NoExtract/#&/' /etc/pacman.conf

# Reinstall glibc to fix missing language files due to missing in the base image
RUN --mount=type=tmpfs,dst=/tmp --mount=type=cache,dst=/usr/lib/sysimage/cache/pacman pacman -Sy glibc --noconfirm

RUN pacman -Syu --noconfirm

RUN pacman -S --noconfirm \
    7zip ark amd-ucode base base-devel bash-completion btop btrfs-progs \
    cpio dbus dbus-glib discover distrobox dolphin dosfstools dracut \
    e2fsprogs efibootmgr fcitx5-anthy fcitx5-im fcitx5-unikey firefox flatpak \
    flatpak-kcm gamescope-session-cachyos git glib2 gptfdisk \
    intel-ucode jq just kate kwalletmanager linux-cachyos \
    linux-cachyos-nvidia-open linux-firmware mangohud man-db mpv nano \
    networkmanager noto-fonts noto-fonts-cjk noto-fonts-extra \
    nvtop opencl-mesa opencl-nvidia openssh ostree parallel\
    partitionmanager pipewire pipewire-jack plasma plasma-login-manager \
    plasma-systemmonitor plymouth plymouth-kcm podman \
    power-profiles-daemon sbctl shadow skopeo starship \
    steam-devices tailscale tlp vulkan-radeon wireplumber \
    xfsprogs yakuake zram-generator

# Copy packages from AUR Builder
RUN mkdir /tmp/built_pkgs
COPY --from=aur-builder /built_pkgs/ /tmp/built_pkgs/
RUN ls /tmp/built_pkgs && pacman -U --noconfirm /tmp/built_pkgs/*.tar.zst && rm -rf /tmp/built_pkgs

# Install fprintd here after CS9311 was installed
RUN pacman -S --noconfirm \
    fprintd

# Cleanup & /opt workaround
COPY build_files/ /

RUN --mount=from=ctx,source=/scripts,target=/scripts,ro \
    bash /scripts/chunkah_stability.sh

RUN pacman -Scc --noconfirm && \
    mv /opt /usr && \
    echo -e "en_US.UTF-8 UTF-8\nen_GB.UTF-8 UTF-8" > /etc/locale.gen && locale-gen && \
    echo -e '\neval $(starship init bash)' >> /etc/bash.bashrc && \
    plymouth-set-default-theme bgrt && \
    systemctl enable NetworkManager power-profiles-daemon bluetooth plasmalogin tlp opt.mount && \
    mkdir -p /usr/lib/bootc/kargs.d/ && \
    echo 'kargs = ["quiet splash zswap.enabled=0"]' > /usr/lib/bootc/kargs.d/00-splash.toml && \
    echo 'Error "UCM support temporary disabled for ${CardLongName}"' >> /usr/share/alsa/ucm2/USB-Audio/Sony/DualSense-PS5.conf


# https://github.com/bootc-dev/bootc/issues/1801
RUN --mount=type=tmpfs,dst=/tmp --mount=type=tmpfs,dst=/root \
    printf "systemdsystemconfdir=/etc/systemd/system\nsystemdsystemunitdir=/usr/lib/systemd/system\n" | tee /usr/lib/dracut/dracut.conf.d/30-bootcrew-fix-bootc-module.conf && \
    printf 'reproducible=yes\nhostonly=no\ncompress=zstd\nadd_dracutmodules+=" plymouth bootc "' | tee "/usr/lib/dracut/dracut.conf.d/30-bootcrew-bootc-container-build.conf" && \
    dracut --force "$(find /usr/lib/modules -maxdepth 1 -type d | grep -v -E "*.img" | tail -n 1)/initramfs.img"

# Necessary for general behavior expected by image-based systems
RUN sed -i 's|^HOME=.*|HOME=/var/home|' "/etc/default/useradd" && \
    rm -rf /boot /home /root /usr/local /srv /opt /mnt /var /usr/lib/sysimage/log /usr/lib/sysimage/cache/pacman/pkg && \
    mkdir -p /sysroot /boot /usr/lib/ostree /var /opt && \
    ln -sT sysroot/ostree /ostree && ln -sT var/roothome /root && ln -sT var/srv /srv && ln -sT var/mnt /mnt && ln -sT var/home /home && ln -sT ../var/usrlocal /usr/local && \
    echo "$(for dir in opt home srv mnt usrlocal ; do echo "d /var/$dir 0755 root root -" ; done)" | tee -a "/usr/lib/tmpfiles.d/bootc-base-dirs.conf" && \
    printf "d /var/roothome 0700 root root -\nd /run/media 0755 root root -" | tee -a "/usr/lib/tmpfiles.d/bootc-base-dirs.conf" && \
    printf '[composefs]\nenabled = yes\n[sysroot]\nreadonly = true\n' | tee "/usr/lib/ostree/prepare-root.conf"

# Setup a temporary root passwd (changeme) for dev purposes
# RUN pacman -S whois --noconfirm
# RUN usermod -p "$(echo "changeme" | mkpasswd -s)" root

# https://bootc-dev.github.io/bootc/bootc-images.html#standard-metadata-for-bootc-compatible-images
LABEL containers.bootc 1

RUN bootc container lint

FROM quay.io/jlebon/chunkah AS chunkah
RUN --mount=from=system,src=/,target=/chunkah,ro \
    --mount=type=bind,target=/run/src,rw \
        chunkah build --max-layers 128 \
          --label containers.bootc=1 \
          > /run/src/out.ociarchive

FROM oci-archive:out.ociarchive
