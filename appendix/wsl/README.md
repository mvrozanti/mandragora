# Appendix: NixOS on Windows Subsystem for Linux (WSL)

While the Mandragora project is explicitly designed as a pure, bare-metal NixOS environment (see [Non-Negotiables in AGENTS.md](../../AGENTS.md#non-negotiables-absolute-rules)), there are scenarios—such as corporate work laptops—where installing bare-metal Linux is impossible. In these cases, you can adapt your Mandragora profile to run under WSL (Windows Subsystem for Linux).

This appendix details how to achieve this using the `nixos-wsl` module.

## 1. System Requirements & Architecture

*   **WSL 2 Only:** NixOS-WSL strictly requires WSL 2 (which uses a real Linux kernel) and the Microsoft Store version of WSL.
*   **Systemd Integration:** The `nixos-wsl` module bridges WSL's initialization process with NixOS's native systemd, allowing most services to run natively.

## 2. Configuration (`wsl.nix`)

To bring the environment to Windows, you must create a new host configuration that strips out hardware-specific modules (audio, graphics drivers, bootloaders, `hardware-configuration.nix`) and replaces them with the `wsl.nix` module. 

Your terminal environment, shells (Zsh), editors (Neovim), and development toolchains remain identical.

### Example Configuration

```nix
{ config, lib, pkgs, ... }:

{
  # Import the nixos-wsl module via flake inputs
  # imports = [ inputs.nixos-wsl.nixosModules.default ];

  wsl = {
    enable = true;
    defaultUser = "m"; # Set to your typical username
    
    # Mounts the Windows C drive at /mnt/c
    # Allows interaction with Windows files directly.
    wslConf.automount.root = "/mnt";
    
    # Allows starting Windows .exe files directly from the Linux shell
    interop.enable = true;
    wslConf.interop.enabled = true;
    wslConf.interop.appendWindowsPath = true;
    
    # Enable native systemd support (required for NixOS services)
    nativeSystemd = true;

    # Optional: Enable to use GPU for CUDA/AI workloads
    # useWindowsDriver = true; 
  };

  # Standard CLI tools
  environment.systemPackages = with pkgs; [
    wget curl git tmux neovim
    wslu # WSL utilities (e.g., wslview to open URLs in Windows browser)
  ];
}
```

## 3. What Works Flawlessly

*   **Dotfiles and CLI:** Zsh, Tmux, Neovim, and all scripts run exactly as on bare metal.
*   **Development:** Compilers (Rust, Go), interpreters (Python), and Nix flakes work natively.
*   **Interop:** You can pipe terminal output to the Windows clipboard (`clip.exe`) or open the current directory in Windows Explorer (`explorer.exe .`).
*   **GUI Apps:** With Windows 11's WSLg, Linux GUI applications (like Alacritty or VSCode) appear as native windows on the desktop.

## 4. Known Limitations

Because WSL is a specialized Hyper-V virtual machine, some bare-metal features cannot be replicated:

*   **Bootloader & Kernel:** You cannot manage the kernel or bootloader via NixOS (`boot.loader.grub` or `boot.kernelPackages` are ignored). WSL manages the kernel.
*   **Hardware Passthrough:** Direct hardware access (like USB devices or security keys) requires third-party tools like `usbipd-win` on the Windows host.
*   **Networking:** WSL uses a NAT network. Services running in WSL are only exposed to the Windows localhost by default. Corporate VPNs on the Windows side often break WSL DNS resolution.
*   **Filesystem Performance:** Accessing Windows files (`/mnt/c/...`) from NixOS incurs a significant performance penalty (the "9P" bottleneck). **Always keep code repositories inside the native WSL filesystem (`/home/m/...`) for optimal speed.**
*   **Docker:** While Docker Desktop offers WSL integration, it is generally recommended to disable it and use the native NixOS Docker engine (`virtualisation.docker.enable = true`) to avoid networking layers and permission conflicts.
