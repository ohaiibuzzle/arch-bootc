FROM docker.io/archlinux/archlinux:latest AS builder

RUN pacman-key --init && \
    pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com && \
    pacman-key --lsign-key F3B607488DB35A47

RUN pacman -U --noconfirm 'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-keyring-20240331-1-any.pkg.tar.zst' \
'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-mirrorlist-22-1-any.pkg.tar.zst' \
'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-v3-mirrorlist-22-1-any.pkg.tar.zst' \
'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-v4-mirrorlist-22-1-any.pkg.tar.zst' \
'https://mirror.cachyos.org/repo/x86_64/cachyos/pacman-7.1.0.r9.g54d9411-2-x86_64.pkg.tar.zst'

RUN echo -e "[cachyos-v3]\nInclude = /etc/pacman.d/cachyos-v3-mirrorlist\n[cachyos-core-v3]\nInclude = /etc/pacman.d/cachyos-v3-mirrorlist\n[cachyos-extra-v3]\nInclude = /etc/pacman.d/cachyos-v3-mirrorlist\n[cachyos]\nInclude = /etc/pacman.d/cachyos-mirrorlist\n" | tee -a /etc/pacman.conf
RUN echo -e "[multilib]\nInclude = /etc/pacman.d/mirrorlist\n" | tee -a /etc/pacman.conf

RUN pacman -Sy --noconfirm base-devel sudo git

RUN useradd builder

RUN echo "builder ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers

RUN mkdir /built_pkgs/

WORKDIR /tmp

RUN sudo -u builder git clone https://aur.archlinux.org/libfprint-cs9711-git.git package && \
    cd package && \
    sudo -u builder makepkg -s --noconfirm && \ 
    cp *.tar.zst /built_pkgs/ && \
    cd ../ && rm -rf package

RUN sudo -u builder git clone https://aur.archlinux.org/visual-studio-code-bin.git package && \
    cd package && \
    sudo -u builder makepkg -s --noconfirm && \ 
    cp *.tar.zst /built_pkgs/ && \
    cd ../ && rm -rf package

FROM docker.io/archlinux/archlinux:latest

# Move everything from `/var` to `/usr/lib/sysimage` so behavior around pacman remains the same on `bootc usroverlay`'d systems
RUN grep "= */var" /etc/pacman.conf | sed "/= *\/var/s/.*=// ; s/ //" | xargs -n1 sh -c 'mkdir -p "/usr/lib/sysimage/$(dirname $(echo $1 | sed "s@/var/@@"))" && mv -v "$1" "/usr/lib/sysimage/$(echo "$1" | sed "s@/var/@@")"' '' && \
    sed -i -e "/= *\/var/ s/^#//" -e "s@= */var@= /usr/lib/sysimage@g" -e "/DownloadUser/d" /etc/pacman.conf

# Remove NoExtract rules, otherwise no additional languages and help pages can be installed
# See https://gitlab.archlinux.org/archlinux/archlinux-docker/-/blob/master/pacman-conf.d-noextract.conf?ref_type=heads
RUN sed -i 's/^[[:space:]]*NoExtract/#&/' /etc/pacman.conf

# Reinstall glibc to fix missing language files due to missing in the base image
RUN --mount=type=tmpfs,dst=/tmp --mount=type=cache,dst=/usr/lib/sysimage/cache/pacman pacman -Sy glibc --noconfirm

RUN pacman-key --init && \
    pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com && \
    pacman-key --lsign-key F3B607488DB35A47

RUN pacman -U --noconfirm 'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-keyring-20240331-1-any.pkg.tar.zst' \
'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-mirrorlist-22-1-any.pkg.tar.zst' \
'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-v3-mirrorlist-22-1-any.pkg.tar.zst' \
'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-v4-mirrorlist-22-1-any.pkg.tar.zst' \
'https://mirror.cachyos.org/repo/x86_64/cachyos/pacman-7.1.0.r9.g54d9411-2-x86_64.pkg.tar.zst'

RUN echo -e "[cachyos-v3]\nInclude = /etc/pacman.d/cachyos-v3-mirrorlist\n[cachyos-core-v3]\nInclude = /etc/pacman.d/cachyos-v3-mirrorlist\n[cachyos-extra-v3]\nInclude = /etc/pacman.d/cachyos-v3-mirrorlist\n[cachyos]\nInclude = /etc/pacman.d/cachyos-mirrorlist\n" | tee -a /etc/pacman.conf
RUN echo -e "[multilib]\nInclude = /etc/pacman.d/mirrorlist\n" | tee -a /etc/pacman.conf

RUN pacman -Syu --noconfirm

RUN pacman -Sy --noconfirm base cpio dracut linux-cachyos linux-cachyos-nvidia-open linux-firmware ostree btrfs-progs e2fsprogs xfsprogs dosfstools skopeo podman dbus dbus-glib glib2 ostree shadow base-devel git yay

RUN yay -S --noconfirm 7zip amd-ucode intel-ucode firefox flatpak flatpak-kcm mpv gamescope-session-cachyos steam-devices plymouth plymouth-kcm plasma gptfdisk nvidia-prime openssh nano opencl-mesa opencl-nvidia starship vulkan-radeon yakuake zram-generator power-profiles-daemon sbctl kwalletmanager jq btrfs-progs pipewire wireplumber pipewire-jack plasma-login-manager discover kate dolphin fcitx5-im fcitx5-unikey fcitx5-anthy nvtop btop plasma-systemmonitor partitionmanager networkmanager noto-fonts noto-fonts-cjk noto-fonts-extra just bash-completion man-db tailscale

RUN mkdir /tmp/built_pkgs
COPY --from=builder /built_pkgs/ /tmp/built_pkgs/
RUN ls /tmp/built_pkgs && pacman -U --noconfirm /tmp/built_pkgs/*.tar.zst && rm -rf /tmp/built_pkgs

RUN systemctl enable NetworkManager power-profiles-daemon bluetooth plasmalogin

RUN yay -Scc --noconfirm

# https://github.com/bootc-dev/bootc/issues/1801
RUN --mount=type=tmpfs,dst=/tmp --mount=type=tmpfs,dst=/root \
    pacman -S --noconfirm rust go-md2man && \
    git clone "https://github.com/bootc-dev/bootc.git" /tmp/bootc && \
    make -C /tmp/bootc bin install-all && \
    printf "systemdsystemconfdir=/etc/systemd/system\nsystemdsystemunitdir=/usr/lib/systemd/system\n" | tee /usr/lib/dracut/dracut.conf.d/30-bootcrew-fix-bootc-module.conf && \
    printf 'reproducible=yes\nhostonly=no\ncompress=zstd\nadd_dracutmodules+=" ostree bootc "' | tee "/usr/lib/dracut/dracut.conf.d/30-bootcrew-bootc-container-build.conf" && \
    dracut --force "$(find /usr/lib/modules -maxdepth 1 -type d | grep -v -E "*.img" | tail -n 1)/initramfs.img" && \
    pacman -Rns --noconfirm rust go-md2man && \
    pacman -S --clean --noconfirm

# Necessary for general behavior expected by image-based systems
RUN sed -i 's|^HOME=.*|HOME=/var/home|' "/etc/default/useradd" && \
    rm -rf /boot /home /root /usr/local /srv /opt /mnt /var /usr/lib/sysimage/log /usr/lib/sysimage/cache/pacman/pkg && \
    mkdir -p /sysroot /boot /usr/lib/ostree /var && \
    ln -sT sysroot/ostree /ostree && ln -sT var/roothome /root && ln -sT var/srv /srv && ln -sT var/opt /opt && ln -sT var/mnt /mnt && ln -sT var/home /home && ln -sT ../var/usrlocal /usr/local && \
    echo "$(for dir in opt home srv mnt usrlocal ; do echo "d /var/$dir 0755 root root -" ; done)" | tee -a "/usr/lib/tmpfiles.d/bootc-base-dirs.conf" && \
    printf "d /var/roothome 0700 root root -\nd /run/media 0755 root root -" | tee -a "/usr/lib/tmpfiles.d/bootc-base-dirs.conf" && \
    printf '[composefs]\nenabled = yes\n[sysroot]\nreadonly = true\n' | tee "/usr/lib/ostree/prepare-root.conf"

# Setup a temporary root passwd (changeme) for dev purposes
# RUN pacman -S whois --noconfirm
# RUN usermod -p "$(echo "changeme" | mkpasswd -s)" root

# https://bootc-dev.github.io/bootc/bootc-images.html#standard-metadata-for-bootc-compatible-images
LABEL containers.bootc 1

RUN bootc container lint
