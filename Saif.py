import os
import sys
import time
import shutil
import subprocess


def run(cmd, shell=True, check=True):
    print(f"\n[RUN] {cmd}")
    result = subprocess.run(cmd, shell=shell, text=True)
    if check and result.returncode != 0:
        raise RuntimeError(f"Command failed: {cmd}")
    return result.returncode


def run_output(cmd, shell=True, check=True):
    print(f"\n[RUN] {cmd}")
    result = subprocess.run(cmd, shell=shell, text=True, capture_output=True)
    if check and result.returncode != 0:
        print(result.stdout)
        print(result.stderr)
        raise RuntimeError(f"Command failed: {cmd}")
    return result.stdout.strip()


def powershell(ps_cmd, check=True):
    cmd = f'powershell -NoProfile -ExecutionPolicy Bypass -Command "{ps_cmd}"'
    return run(cmd, check=check)


def powershell_output(ps_cmd, check=True):
    cmd = f'powershell -NoProfile -ExecutionPolicy Bypass -Command "{ps_cmd}"'
    return run_output(cmd, check=check)


def ensure_windows():
    if os.name != "nt":
        raise EnvironmentError("This script only works on Windows.")


def ensure_admin():
    import ctypes
    try:
        is_admin = ctypes.windll.shell32.IsUserAnAdmin()
    except Exception:
        is_admin = False

    if not is_admin:
        raise PermissionError("Run this script as Administrator.")


def install_tailscale():
    if shutil.which("tailscale"):
        print("[OK] Tailscale already installed.")
        return

    if not shutil.which("choco"):
        raise RuntimeError("Chocolatey not found. Install Chocolatey first or install Tailscale manually.")

    print("[INFO] Installing Tailscale...")
    run("choco install tailscale -y")


def connect_tailscale():
    ts_authkey = os.environ.get("TS_AUTHKEY")
    if not ts_authkey:
        raise ValueError("TS_AUTHKEY environment variable not set.")

    print("[INFO] Connecting to Tailscale...")
    run(f'tailscale up --authkey="{ts_authkey}" --hostname="python-windows-rdp"')


def enable_rdp(disable_nla=True):
    print("[INFO] Enabling RDP...")
    powershell(
        r"Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' "
        r"-Name 'fDenyTSConnections' -Value 0"
    )

    powershell(r"Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'")

    if disable_nla:
        print("[INFO] Disabling NLA...")
        powershell(
            r"Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' "
            r"-Name 'UserAuthentication' -Value 0"
        )
    else:
        print("[INFO] Keeping NLA enabled...")


def set_rdp_password():
    rdp_password = os.environ.get("RDP_PASSWORD")
    if not rdp_password:
        raise ValueError("RDP_PASSWORD environment variable not set.")

    print("[INFO] Setting password for runneradmin...")
    ps = (
        f"$Password = ConvertTo-SecureString '{rdp_password}' -AsPlainText -Force; "
        f"Set-LocalUser -Name 'runneradmin' -Password $Password; "
        f"Add-LocalGroupMember -Group 'Remote Desktop Users' -Member 'runneradmin' -ErrorAction SilentlyContinue"
    )
    powershell(ps)


def show_tailscale_ip():
    print("[INFO] Tailscale IPv4:")
    ip = run_output("tailscale ip -4")
    print(ip)
    return ip


def keep_alive(seconds=21600):
    print(f"[INFO] Keeping alive for {seconds} seconds...")
    while seconds > 0:
        print(f"[INFO] Remaining: {seconds} seconds")
        time.sleep(min(60, seconds))
        seconds -= 60


def main():
    ensure_windows()
    ensure_admin()

    # Change to False if you want to keep NLA enabled
    DISABLE_NLA = True

    install_tailscale()
    connect_tailscale()
    enable_rdp(disable_nla=DISABLE_NLA)
    set_rdp_password()
    ip = show_tailscale_ip()

    print("\n========== RDP DETAILS ==========")
    print(f"Host: {ip}")
    print("Username: runneradmin")
    print("Password: <from RDP_PASSWORD env>")
    print("=================================\n")

    keep_alive()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"[ERROR] {e}")
        sys.exit(1)
