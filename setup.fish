#!/usr/bin/env fish
# Setup script to replicate CachyOS + Hyprland + Caelestia environment
# Run after a fresh CachyOS install

set script_dir (dirname (realpath (status filename)))

function log
    set_color cyan
    echo ":: $argv"
    set_color normal
end

function warn
    set_color yellow
    echo ":: $argv"
    set_color normal
end

function err
    set_color red
    echo ":: $argv"
    set_color normal
end

# Check we're on CachyOS/Arch
if ! test -f /etc/pacman.conf
    err "This script requires an Arch-based system (CachyOS recommended)"
    exit 1
end

log "Starting setup..."

# ──────────────────────────────────────────────
# 1. Install paru (AUR helper)
# ──────────────────────────────────────────────
if ! command -q paru
    log "Installing paru..."
    sudo pacman -S --needed --noconfirm git base-devel
    set -l tmpdir (mktemp -d)
    git clone https://aur.archlinux.org/paru.git $tmpdir/paru
    cd $tmpdir/paru && makepkg -si --noconfirm
    cd $script_dir
    rm -rf $tmpdir
    paru --gendb
else
    log "paru already installed"
end

# ──────────────────────────────────────────────
# 2. Install official packages
# ──────────────────────────────────────────────
log "Installing official packages..."

# Filter out hardware-specific packages
set -l skip_patterns \
    'nvidia' \
    'intel-ucode' \
    'intel-media'

set -l pkgs
for pkg in (cat $script_dir/pkgs-official.txt)
    set -l should_skip false
    for pattern in $skip_patterns
        if string match -q "*$pattern*" $pkg
            set should_skip true
            break
        end
    end
    if test $should_skip = false
        set -a pkgs $pkg
    end
end

sudo pacman -S --needed --noconfirm $pkgs

# ──────────────────────────────────────────────
# 3. Detect and install hardware-specific packages
# ──────────────────────────────────────────────
log "Detecting hardware..."

# CPU microcode
set -l cpu_vendor (grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}')
if test "$cpu_vendor" = "GenuineIntel"
    log "Intel CPU detected, installing intel-ucode + media drivers..."
    sudo pacman -S --needed --noconfirm intel-ucode intel-media-driver intel-media-sdk
else if test "$cpu_vendor" = "AuthenticAMD"
    log "AMD CPU detected, installing amd-ucode..."
    sudo pacman -S --needed --noconfirm amd-ucode
end

# GPU
if lspci | grep -qi 'nvidia'
    log "NVIDIA GPU detected"
    warn "Install NVIDIA drivers manually — version depends on your GPU"
    warn "  For recent GPUs:  sudo pacman -S nvidia-dkms nvidia-utils"
    warn "  For older GPUs:   check https://wiki.archlinux.org/title/NVIDIA"
end

if lspci | grep -qi 'intel.*graphics\|intel.*iris'
    log "Intel GPU detected, installing Vulkan drivers..."
    sudo pacman -S --needed --noconfirm vulkan-intel lib32-vulkan-intel
end

# ──────────────────────────────────────────────
# 4. Install AUR packages
# ──────────────────────────────────────────────
log "Installing AUR packages..."
paru -S --needed --noconfirm (cat $script_dir/pkgs-aur.txt)

# ──────────────────────────────────────────────
# 5. Install Caelestia dotfiles
# ──────────────────────────────────────────────
set -l caelestia_dir $HOME/.local/share/caelestia

if ! test -d $caelestia_dir
    log "Cloning Caelestia dotfiles..."
    git clone https://github.com/caelestia-dots/caelestia.git $caelestia_dir
else
    log "Caelestia already cloned, pulling latest..."
    git -C $caelestia_dir pull
end

log "Running Caelestia installer..."
fish $caelestia_dir/install.fish --noconfirm --vscode=codium

# ──────────────────────────────────────────────
# 6. Apply personal overrides
# ──────────────────────────────────────────────
log "Applying personal configuration overrides..."

set -l caelestia_config $HOME/.config/caelestia
mkdir -p $caelestia_config

cp $script_dir/configs/caelestia/hypr-user.conf $caelestia_config/
cp $script_dir/configs/caelestia/hypr-vars.conf $caelestia_config/
cp $script_dir/configs/caelestia/shell.json $caelestia_config/

# Foot terminal config
log "Applying foot terminal config..."
mkdir -p $HOME/.config/foot
cp $script_dir/configs/foot/foot.ini $HOME/.config/foot/

# ──────────────────────────────────────────────
# 7. Fix Hyprland monitor layout marker
# ──────────────────────────────────────────────
log "Fixing monitor layout marker in hyprland.conf..."
set -l hypr_conf $HOME/.config/hypr/hyprland.conf
if test -f $hypr_conf
    sed -i 's/^# Default monitor conf$/# Monitor layout/' $hypr_conf
end

# ──────────────────────────────────────────────
# 8. Fix icon theme for Qt (Papirus-Dark missing large icons)
# ──────────────────────────────────────────────
log "Fixing Qt icon theme..."
for conf in $HOME/.config/qt5ct/qt5ct.conf $HOME/.config/qt6ct/qt6ct.conf
    if test -f $conf
        sed -i 's/^icon_theme=Papirus-Dark$/icon_theme=Papirus/' $conf
    end
end

# Ensure Qt reads qt6ct config (needed for Quickshell icon theme)
mkdir -p $HOME/.config/environment.d
cp $script_dir/configs/environment.d/qt.conf $HOME/.config/environment.d/

# Symlink missing large icons in Papirus-Dark
log "Fixing missing Papirus-Dark icons..."
for size in 22x22 24x24 32x32 48x48 64x64
    sudo mkdir -p /usr/share/icons/Papirus-Dark/$size/places
    sudo ln -sf /usr/share/icons/Papirus/$size/places/inode-directory.svg \
        /usr/share/icons/Papirus-Dark/$size/places/inode-directory.svg
    sudo ln -sf /usr/share/icons/Papirus/$size/places/folder.svg \
        /usr/share/icons/Papirus-Dark/$size/places/folder.svg
end
sudo gtk-update-icon-cache -f /usr/share/icons/Papirus-Dark/

# ──────────────────────────────────────────────
# 9. Install custom scripts
# ──────────────────────────────────────────────
log "Installing custom scripts..."

mkdir -p $HOME/.local/bin
cp $script_dir/scripts/* $HOME/.local/bin/
chmod +x $HOME/.local/bin/*

# ──────────────────────────────────────────────
# 10. Set fish as default shell
# ──────────────────────────────────────────────
if test (basename $SHELL) != fish
    log "Setting fish as default shell..."
    chsh -s /usr/bin/fish
else
    log "fish is already the default shell"
end

# ──────────────────────────────────────────────
# 11. Enable services
# ──────────────────────────────────────────────
log "Enabling system services..."

set -l services \
    NetworkManager \
    bluetooth \
    docker \
    ollama \
    sddm

for svc in $services
    if systemctl list-unit-files | grep -q "^$svc.service"
        sudo systemctl enable --now $svc
    end
end

# Add user to docker group
sudo usermod -aG docker $USER

# ──────────────────────────────────────────────
# 12. Pull Ollama models
# ──────────────────────────────────────────────
log "Pulling Ollama models..."
ollama pull nomic-embed-text

# ──────────────────────────────────────────────
# 13. Done
# ──────────────────────────────────────────────
log ""
log "Setup complete!"
log ""
log "Remaining manual steps:"
log "  1. Reboot"
log "  2. Configure monitors with: wdisplays-save"
log "  3. Set a wallpaper with: caelestia wallpaper -r ~/Pictures/Wallpapers/"
log "  4. Install NVIDIA drivers if needed (see message above)"
log ""
