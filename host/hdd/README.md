# HDD (`/mnt/hdd`): mount, gated stacks, failure email

The internal SpinPoint F3 HDD (`sdb1`, UUID `e8930f74-e5fe-4843-b256-c8f249ff9738`) holds Navidrome's music and Immich's originals. Its own older data (`CD/`, `Music/`, …) stays in the root of the disk. New data goes under `/mnt/hdd/srv/`.

**Design**
- **Only Navidrome and Immich depend on the HDD.** `hdd-stacks.service` starts them after the mount and stops them if the mount goes away. Docker, AdGuard and everything else start normally without the HDD.
- **Two safety nets against "empty directory = data deleted":**
  - `/mnt/hdd` is an immutable (`chattr +i`) empty directory when nothing is mounted.
  - The compose files bind HDD paths with `create_host_path: false`, so Docker refuses to start these containers when the HDD is missing.
- **Failure emails go through the existing Alertmanager**, which uses the Proton Bridge relay, to `polymatheiia@proton.me`. They're sent:
  - by `smartd` when SMART health fails, attributes go bad, self-tests fail or the temperature reaches 55 °C
  - by `hdd-health-check.timer` (hourly) when the disk is missing or not mounted, the filesystem is read-only, the kernel logs I/O or link errors, or the UDMA CRC counter rises
  - by `OnFailure=` when the mount unit or `hdd-stacks.service` fails
- **Limit:** Alertmanager runs in Docker, so if Docker itself is down, alerts are only logged (`journalctl -t hdd-alert`).

## Files

| Here | Installed to |
|---|---|
| `fstab.line` | appended to `/etc/fstab` (`nofail` is safe because nothing outside the gated stacks depends on the HDD) |
| `bin/hdd-alert`, `bin/hdd-smartd-alert`, `bin/hdd-health-check` | `/usr/local/bin/` |
| `systemd/hdd-alert@.service`, `hdd-stacks.service`, `hdd-health-check.{service,timer}` | `/etc/systemd/system/` |
| `systemd/mnt-hdd.mount.d/alert.conf` | `/etc/systemd/system/mnt-hdd.mount.d/` |
| `smartd.conf` | `/etc/smartd.conf` (the original is kept as `.orig`) |
| `navidrome-compose.patch`, `immich-compose.patch` | applied to `services/*/docker-compose.yml` at move time |

## Install (run as your user with sudo, after the long SMART test has passed)

```bash
cd /srv/pm_homelab/host/hdd
sudo smartctl -l selftest /dev/sdb          # want: "Completed without error" on top

# 1. mountpoint + fstab
sudo mkdir -p /mnt/hdd && sudo chattr +i /mnt/hdd
grep -q e8930f74 /etc/fstab || sudo tee -a /etc/fstab < fstab.line
sudo systemctl daemon-reload && sudo mount /mnt/hdd
sudo install -d -m 755 /mnt/hdd/srv && sudo touch /mnt/hdd/srv/.hdd-marker

# 2. scripts, units, smartd
sudo install -m 755 bin/* /usr/local/bin/
sudo install -m 644 systemd/*.service systemd/*.timer /etc/systemd/system/
sudo install -D -m 644 systemd/mnt-hdd.mount.d/alert.conf /etc/systemd/system/mnt-hdd.mount.d/alert.conf
sudo cp -n /etc/smartd.conf /etc/smartd.conf.orig && sudo install -m 644 smartd.conf /etc/smartd.conf
sudo systemctl daemon-reload
sudo systemctl enable --now smartd.service hdd-health-check.timer

# 3. test the email path (you should get one mail within ~1 min)
sudo /usr/local/bin/hdd-alert HDDTest "Test alert from forestmachine" "Ignore: install test"
sudo systemctl start hdd-health-check.service; systemctl status hdd-health-check.service --no-pager
```

Do **not** enable `hdd-stacks.service` yet. It belongs to the move below.

## Move music (Navidrome)

```bash
docker stop navidrome
sudo install -d -o 1000 -g 1000 /mnt/hdd/srv/media
sudo rsync -aHAX --info=progress2 /srv/media/music/ /mnt/hdd/srv/media/music/
sudo rsync -aHAXc --dry-run --itemize-changes /srv/media/music/ /mnt/hdd/srv/media/music/   # must print nothing
cd /srv/pm_homelab && git apply -p1 host/hdd/navidrome-compose.patch
docker compose -f services/navidrome/docker-compose.yml up -d
```
Check that the track count in Navidrome is unchanged and that a song plays.

## Move Immich originals

```bash
docker compose -f /srv/pm_homelab/services/immich/docker-compose.yml stop
for d in library upload backups; do
  sudo rsync -aHAX --info=progress2 /srv/immich/library/$d/ /mnt/hdd/srv/immich/$d/
  sudo rsync -aHAXc --dry-run --itemize-changes /srv/immich/library/$d/ /mnt/hdd/srv/immich/$d/   # must print nothing
done
cd /srv/pm_homelab && git apply -p1 host/hdd/immich-compose.patch
docker compose -f services/immich/docker-compose.yml up -d
```
Check:
- old photos open at full size
- a new phone upload appears under `/mnt/hdd/srv/immich/upload`
- Administration → Jobs shows no errors

## Then turn on the gate

```bash
sudo systemctl enable --now hdd-stacks.service
```

Optional test, which stops Navidrome and Immich briefly: `sudo umount /mnt/hdd`. Expected:
- both stacks stop
- `docker start navidrome` fails with "bind source path does not exist"
- within the hour, the health check sends an email

Then run `sudo mount /mnt/hdd && sudo systemctl start hdd-stacks.service`.

## Clean up (after a few days of normal use)
Delete the SSD copies only then. Look at each path first:
- `sudo rm -rf /srv/media/music`
- `sudo rm -rf /srv/immich/library/{library,upload,backups}`

Leave the empty directories in place: `/data/library` and the rest are mount targets.

## Notes and rollback
- **Rollback, compose:** `git checkout services/navidrome/docker-compose.yml services/immich/docker-compose.yml` brings back the SSD paths. Valid until the SSD copies are deleted.
- **Rollback, host:** `sudo systemctl disable --now hdd-stacks.service hdd-health-check.timer smartd`, delete the installed files, put back `/etc/smartd.conf.orig`, remove the fstab line, then `sudo chattr -i /mnt/hdd`.
- **Ansible:** `services/` is synced from this same checkout, so the patched compose files are what Ansible deploys. Commit them along with `host/hdd/`. If the HDD is missing, an Ansible run fails at "Deploy always-on services" for these two stacks, which is intended.
- **Hibernate:** smartd self-tests are scheduled at 03:00 and 04:00 on Sundays. That works while the nightly hibernate is broken. If you fix it, move the `-s` schedule to daytime.
- **Spin-down:** check with `sudo hdparm -C /dev/sdb`. If the disk goes to standby and Navidrome's first song is slow, run `sudo hdparm -S 0 /dev/sdb` and add a udev rule to keep it.
