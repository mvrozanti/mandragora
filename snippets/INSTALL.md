# Install Sequence

## Prerequisites
- NixOS live USB booted
- Internet connection (ethernet recommended)
- This repo cloned or copied to the live environment

## Steps

### 1. Clone the repo
```bash
git clone <your-repo> /tmp/mandragora
cd /tmp/mandragora
```

### 2. Partition the drive
```bash
sudo bash snippets/format-drive.sh /dev/nvme0n1
```

### 3. Mount subvolumes
```bash
sudo bash snippets/mount-install.sh
```

### 4. Get required tools
```bash
nix shell nixpkgs#age nixpkgs#sops
```

### 5. Generate age key and encrypt secrets
```bash
sudo bash snippets/bootstrap-age-key.sh
```
You will be prompted for a password for user `m`. This is your login password.

The encrypted secrets file is written to `secrets/secrets.yaml`. The age key lives at `/mnt/persistent/secrets/keys.txt` — **back this up somewhere safe**. Losing it locks you out of all secrets.

### 6. Install NixOS
```bash
sudo bash snippets/install.sh
```

### 7. Reboot
```bash
reboot
```

Log in as `m` with the password you set in step 5.

---

## After first boot — Shadow profile (optional)

To initialize the encrypted Shadow home image:
```bash
sudo bash snippets/setup-shadow.sh
```
