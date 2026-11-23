# Troubleshooting

Every problem below happened during the real build. Each entry has the **symptom**, the **cause** and the **fix**.

---

## Installer: "Installation Not Supported for this Operating System"

**Symptom:** `install.sh` exits right after the license prompt.

**Cause:** Ubuntu **26.04** was installed. Kasm 1.19 supports Ubuntu 22.04 / 24.04 only.

**Fix:** reinstall the VM with **Ubuntu Server 24.04 LTS**. Check with `lsb_release -a` before installing Kasm.

---

## VirtualBox unattended install fails (`vboxpostinstall.sh ... exit status 1`)

**Symptom:** Ubuntu install ends with *"An error occurred. Press enter to start a shell"*, or you can't log in afterwards (the default user is `vboxuser`, with password `changeme`).

**Cause:** selecting the ISO in the *New VM* dialog starts VirtualBox's unattended installer, and its post-install script failed.

**Fix:** create the VM with **no ISO selected**, then attach the ISO under **Settings → Storage**. You get Ubuntu's normal interactive installer.

---

## Bridged networking gives 10.0.2.15 / no LAN address

**Cause:** the adapter was still on NAT, or Wi-Fi bridging was unreliable.

**Fix:** stay on **NAT** and use port forwarding (`127.0.0.1:8443 → 443`, `127.0.0.1:2222 → 22`). Cloudflare Tunnel only needs outbound internet, so NAT is enough.

---

## `curl: command not found` / installer files missing after reboot

**Cause:** Ubuntu Server doesn't always include `curl`, and `/tmp` is emptied on every boot.

**Fix:** run `sudo apt install -y curl` and download the Kasm release into `~`, not `/tmp`.

---

## Docker plugin fails: `kasmnetwork.sock` / `kasmlogger.sock` connection refused / no such file

**Symptoms:**

```
Installing docker sidecar network plugin
Error response from daemon: dial unix /run/docker/plugins/<id>/kasmnetwork.sock: connect: connection refused
```

```
Installing docker logging plugin: kasmweb/kasm-logging-plugin
Error response from daemon: dial unix /run/docker/plugins/<id>/kasmlogger.sock: connect: no such file or directory
```

`docker plugin ls` shows the plugin with `ENABLED false`, but `docker plugin enable <name>` run a minute later works. The plugin's own log (`/var/log/kasm-sidecar/plugin.log`) shows it *did* start listening.

**Cause:** Docker waits only a few seconds for a managed plugin to open its socket. On a slow VM the plugin (a small Python server) starts too late, so Docker marks it failed and the installer exits.

**Fixes:**

1. Install [`scripts/docker-plugin-retry-wrapper.sh`](../scripts/docker-plugin-retry-wrapper.sh) as `/usr/local/bin/docker`. `sudo` finds `/usr/local/bin` before `/usr/bin`, so the installer uses it. It installs plugins disabled, then retries `enable` up to 12 times.
2. Install with `--skip-egress`. The sidecar/egress plugin is only for routing workspace traffic through VPN providers.
3. Before re-running the installer, clean up the half-finished install:

   ```bash
   for p in $(sudo docker plugin ls --format '{{.Name}}' | grep kasm); do sudo docker plugin rm -f $p; done
   sudo docker network rm kasm_default_network
   sudo rm -rf /opt/kasm
   ```

4. After a reboot, Docker restores plugins with the same short timer. [`systemd/kasm-plugins.service`](../systemd/kasm-plugins.service) re-enables them before Kasm starts.

---

## `WARNING: IPv4 forwarding is disabled`

**Fix:** turn it on permanently:

```bash
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-kasm.conf
sudo sysctl --system && sudo systemctl restart docker
```

This warning wasn't the cause of the plugin failures, but it's correct to fix it.

---

## VirtualBox runs in "turtle mode" (Hyper-V / VBS)

**Symptoms:** a green turtle icon in the VM status bar, or *Machine → Session Information → Execution engine: native API*. Everything in the VM is very slow, and it's the root cause of the plugin timeouts above.

**Cause:** Windows' hypervisor is running, so VirtualBox must use the slow Hyper-V backend. `msinfo32` shows *Virtualization-based security: Running* and *A hypervisor has been detected*.

**Things to try (in this order):**

1. Turn off **Core isolation → Memory integrity**.
2. Untick **Hyper-V, Virtual Machine Platform, Windows Hypervisor Platform, WSL, Windows Sandbox** in *Turn Windows features on or off*.
3. Run `bcdedit /set hypervisorlaunchtype off`, then do a **real restart** (`shutdown /r /t 0`). Fast Startup means a plain "Shut down" doesn't reload the hypervisor setting.
4. `gpedit.msc` → *System → Device Guard → Turn On Virtualization Based Security* → **Disabled**.

On the build machine VBS **stayed on** even after all of this. It was most likely enforced by firmware or a management policy (the machine showed *App Control for Business: Enforced*). The workarounds in this repo, plus the **virtio-net** network card, made it usable anyway.

**Alternative:** create the VM in **Hyper-V** itself, which runs at native speed. Convert the disk with
`VBoxManage clonemedium disk kasm1.vdi kasm1.vhd --format VHD`, create a Generation 1 VM on the *Default Switch*, then update the interface name in `/etc/netplan/*.yaml`.

---

## Installer stuck on "Starting Kasm Services" for a long time

**Cause:** the service images (several GB) download and unpack slowly on a slow VM.

**Check progress:** `sudo journalctl -u kasm -f`. It finishes with `Finished kasm.service`.

---

## `kasm_api` keeps restarting / login returns 502

**Symptoms:** *Login Failed: Request failed with status code 502*, both locally and through the tunnel. `docker ps` shows `kasm_api  Restarting (140)`. Its logs show:

```
[ERROR] root: Healthcheck failure detected. Gracefully shutting down.
```

`top` shows `ksoftirqd` at ~80% CPU, high `si` (software interrupts), and a load average of 25+ on 8 cores.

**Cause:** the emulated **Intel PRO/1000** network card is very expensive in turtle mode. Interrupt handling ate the CPU, so the API's self-check timed out and it shut itself down in a loop.

**Fix:** power off the VM → **Settings → Network → Adapter 1 → Advanced → Adapter Type: Paravirtualized Network (virtio-net)**. On Ubuntu the interface name stayed `enp0s3`. Afterwards the load average dropped to about 2 and all containers were healthy.

---

## Workspace starts but never appears (black screen / endless loading)

**Symptom:** the admin panel shows the session as `running`, but the browser shows nothing.

**Cause:** Kasm told the browser to connect on port 443, while the user reached Kasm on 8443 (VirtualBox port forward) or through the tunnel.

**Fix:** **Infrastructure → Zones → default → Proxy Port = `0`** (auto-detect). Then delete the old session and start a new one.

---

## Log spam: `GPU caps helper stderr: VMware: No 3D enabled`

Harmless. The VM has no 3D GPU, and workspaces render in software.

---

## Agent heartbeat: `Read timed out (read timeout=60)`

The Kasm agent asked Docker for its image list and waited more than 60 s, usually while a large image was downloading on a slow VM. It recovers by itself. If it keeps happening, see *turtle mode* above.

---

## cloudflared service fails to start, token file missing

**Symptoms:**

```
Job for cloudflared.service failed because a timeout was exceeded.
...
Failed to read token file: open /etc/cloudflared/token: no such file or directory
```

**Cause:** on a slow VM, cloudflared connects to Cloudflare slower than systemd's default start timeout. `service install` treats that as a failure and **deletes the token file**, and every restart after that fails.

**Fix:**

```bash
sudo mkdir -p /etc/systemd/system/cloudflared.service.d
printf '[Service]\nTimeoutStartSec=300\n' | sudo tee /etc/systemd/system/cloudflared.service.d/override.conf
sudo nano /etc/cloudflared/token        # paste ONLY the token (eyJ...)
sudo chmod 600 /etc/cloudflared/token
sudo systemctl daemon-reload && sudo systemctl restart cloudflared
sudo journalctl -u cloudflared -n 15 | grep -i registered
```

---

## `apt` lock held by another process

```
E: Could not get lock /var/lib/apt/lists/lock. It is held by process ... (apt-get)
```

Ubuntu's automatic updates are running. Wait for them to finish:

```bash
while sudo fuser /var/lib/apt/lists/lock /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 10; done
```

---

## Cloudflare DNS import: existing website or email breaks

When the domain already hosts a website or email (for example cPanel), set the imported records to **DNS only (grey cloud)**. An MX record must not point at a proxied name, and FTP/IMAP/SMTP can't go through the Cloudflare proxy. The tunnel's own hostname is created separately and is proxied automatically.

---

## First Chrome session is very slow, later ones are fine

The first launch after a boot loads the 4.8 GB image from disk, creates the Chrome profile and warms the caches. Give it a minute. Test with 2–3 users at once before inviting everyone.
