# Setup guide

This guide follows the order used in the real build. Replace these placeholders with your own values:

| Placeholder | Meaning |
|---|---|
| `kasm1` | VirtualBox VM name |
| `<user>` | Your Ubuntu username |
| `example.com` | Your domain |
| `kasm.example.com` | The address users will open |

---

## 1. Windows host

Open PowerShell **as Administrator** and run [`windows/server-power-settings.ps1`](../windows/server-power-settings.ps1), or run these commands by hand:

```powershell
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
powercfg /hibernate off
powercfg /change monitor-timeout-ac 10
```

Also:

- **Device Manager → Network adapters →** each physical adapter → **Power Management** → untick *"Allow the computer to turn off this device to save power"*.
- **Windows Update → Advanced options:** set wide **Active hours**, and turn on *Notify me when a restart is required*. On Windows Pro you can also set `gpedit.msc` → *Windows Update → Manage end user experience* → **No auto-restart with logged on users…** → Enabled.
- **BIOS/UEFI:** set *Restore on AC Power Loss* to **Power On**.
- Prefer an **Ethernet cable** over Wi-Fi.

### Check: is Windows' hypervisor running?

Run `msinfo32` and look at **Virtualization-based security** and **"A hypervisor has been detected"**. If the hypervisor is running, VirtualBox uses the slow Hyper-V backend (a green turtle icon in the VM status bar). The build still works with the fixes in this repo, but see [troubleshooting](troubleshooting.md#virtualbox-runs-in-turtle-mode-hyper-v--vbs).

---

## 2. Create the VirtualBox VM

1. **New VM:** name `kasm1`, type Linux / Ubuntu 64-bit. **Leave the ISO field empty** so the VirtualBox unattended installer does not run (it failed twice in this build).
2. Resources: 12 GB+ RAM, 8 vCPUs, 200 GB dynamically allocated disk.
3. **Settings → Storage:** attach `ubuntu-24.04.x-live-server-amd64.iso` to the optical drive.
4. **Settings → Network → Adapter 1:**
   - Attached to: **NAT**
   - Advanced → Adapter Type: **Paravirtualized Network (virtio-net)**. This is important on slow hosts; see [troubleshooting](troubleshooting.md#kasm_api-keeps-restarting--login-returns-502).
   - Port Forwarding:

     | Name | Protocol | Host IP | Host Port | Guest Port |
     |---|---|---|---|---|
     | kasm | TCP | 127.0.0.1 | 8443 | 443 |
     | ssh | TCP | 127.0.0.1 | 2222 | 22 |

---

## 3. Install Ubuntu Server 24.04

- Type of install: **Ubuntu Server** (not minimized)
- Storage: use the entire disk, and untick **LVM** so the whole disk is usable
- Tick **Install OpenSSH server**
- No snaps

After the reboot, connect from Windows:

```powershell
ssh -p 2222 <user>@localhost
```

Then update and install the basics:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl
```

---

## 4. Install Kasm Workspaces

### 4.1 Docker plugin retry wrapper (slow hosts)

Docker gives a plugin only a few seconds to open its socket. On a slow VM, Kasm's plugins miss that window and the installer aborts. The wrapper retries instead.

The wrapper calls the real Docker at `/usr/bin/docker`, so **Docker must be installed first**. The Kasm installer accepts an existing supported Docker and doesn't replace it.

```bash
curl -fsSL https://get.docker.com | sudo sh     # skip if Docker is already installed
ls -l /usr/bin/docker                            # must exist
```

> In the original build, Docker was installed by a first (failed) run of the Kasm installer. Either way works.

Then install the wrapper:

```bash
sudo cp scripts/docker-plugin-retry-wrapper.sh /usr/local/bin/docker
sudo chmod +x /usr/local/bin/docker
sudo which docker      # must print /usr/local/bin/docker
```

It only changes `docker plugin install` and `docker plugin enable`. Every other command is passed straight to `/usr/bin/docker`.

### 4.2 Kernel IP forwarding

```bash
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-kasm.conf
sudo sysctl --system
```

### 4.3 Install

Download into your home folder, because `/tmp` is wiped on reboot:

```bash
cd ~
curl -fO https://kasm-static-content.s3.amazonaws.com/kasm_release_1.19.0.tar.gz
tar -xf kasm_release_1.19.0.tar.gz
sudo bash kasm_release/install.sh --swap-size 8192 --skip-egress
```

- `--swap-size 8192` creates the swap Kasm requires.
- `--skip-egress` skips the VPN-egress network plugin, which kept failing to start and isn't needed for normal internet access in workspaces.
- On a slow host, *"Starting Kasm Services"* can take 30–60+ minutes while images download. Watch it with `sudo journalctl -u kasm -f`.
- **Save the credentials printed at the end.**

Check the result:

```bash
sudo docker ps --format "table {{.Names}}\t{{.Status}}"
curl -k https://localhost/api/__healthcheck     # {"ok": true}
```

### 4.4 Survive reboots

```bash
sudo cp scripts/kasm-fix-plugins.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/kasm-fix-plugins.sh
sudo cp systemd/kasm-plugins.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable kasm-plugins.service
```

---

## 5. Configure Kasm

Open `https://localhost:8443` on the Windows host and log in as `admin@kasm.local`.

1. **Change the admin password**, and change or delete `user@kasm.local`.
2. **Infrastructure → Zones → default → Proxy Port = `0`.** Without this, sessions start but never display when Kasm is reached on a different port (8443 locally, 443 via the tunnel).
3. **Workspaces → Registry:** install **Chrome** (about 4.8 GB).
4. **Users → Add User**, one per person. Keep them only in **All Users**, never in Administrators.
5. **Persistent profiles:**

   ```bash
   sudo mkdir -p /mnt/kasm_profiles
   sudo chown -R 1000:1000 /mnt/kasm_profiles
   ```

   - **Workspaces → Chrome → Edit → Persistent Profile Path:** `/mnt/kasm_profiles/{username}/{image_id}`
   - **Groups → All Users → Settings:** `allow_persistent_profile` = `True`
6. **Groups → All Users → Settings:** `max_kasms_per_user` = `1`, so one user can't take all 5 Community Edition slots.

Users choose **Persistent Profile: Enabled** when they start Chrome, and should end with **Delete Session** from the Kasm menu.

---

## 6. Cloudflare: domain and tunnel

### 6.1 Move DNS to Cloudflare (domain stays at your registrar)

1. Cloudflare dashboard → **Add a site → Connect a domain** → Free plan.
2. Review the imported records. If the domain already hosts a website or email, keep those records **DNS only (grey cloud)**, especially anything an MX record points to.
3. At your registrar, replace the nameservers with the two Cloudflare ones. Turn off DNSSEC first.
4. Wait for the domain to show **Active**.

### 6.2 Create the tunnel (inside the VM)

1. **Networking → Tunnels → Create tunnel → Cloudflared**, then choose **Debian / 64-bit** (this is correct for Ubuntu too).
2. Run the repository and install commands Cloudflare shows. If `apt` reports a lock, wait for unattended upgrades to finish:

   ```bash
   while sudo fuser /var/lib/apt/lists/lock /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 10; done
   ```

3. **On slow hosts, add the start timeout first**, or the service install times out and deletes the token file:

   ```bash
   sudo mkdir -p /etc/systemd/system/cloudflared.service.d
   sudo cp systemd/cloudflared-override.conf /etc/systemd/system/cloudflared.service.d/override.conf
   sudo systemctl daemon-reload
   ```

4. Run `sudo cloudflared service install <TOKEN>`. If it still fails, see [troubleshooting](troubleshooting.md#cloudflared-service-fails-to-start-token-file-missing).
5. Check: `sudo journalctl -u cloudflared | grep "Registered tunnel connection"`.

### 6.3 Route

Add a published application route (public hostname) on the tunnel:

| Field | Value |
|---|---|
| Subdomain / Domain | `kasm` / `example.com` |
| Service | `https://localhost:443` |
| Disable TLS certificate verification | **On** (Kasm uses a self-signed certificate) |
| Use HTTP/2 to origin | **On** |

Test from a phone on mobile data: `https://kasm.example.com`.

---

## 7. Start the VM automatically

Run [`windows/register-vm-autostart.ps1`](../windows/register-vm-autostart.ps1) as Administrator. It registers a scheduled task that runs at startup:

```
VBoxManage.exe startvm "kasm1" --type headless
```

**Final test:** restart Windows, don't log in, and after 10–15 minutes open `https://kasm.example.com` from another device.
